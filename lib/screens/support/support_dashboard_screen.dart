// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/auth_service.dart';
import '../../services/canned_responses_service.dart';
import '../../services/support_agent_service.dart';
import '../../services/user_roles.dart';
import '../../utils/safe_image_provider.dart';
import '../../widgets/trust_score_bar.dart';
import '../role_switcher_screen.dart';

/// Support Workspace — the home screen for users with role 'support_agent'
/// (and a tool admins can also use to triage tickets).
///
/// Layout: 3-pane split-screen optimized for desktop.
///   • Left  (~280px): TicketQueuePane    — filters + ticket list with SLA timers
///   • Center (flex):  Customer360Pane    — chat + customer info bar
///   • Right (~360px): ActionCenterPane   — context panels + agent actions
///
/// All sensitive actions go through SupportAgentService → supportAgentAction CF
/// which writes to support_audit_log. Internal notes are filtered out from
/// the customer's view via Firestore rules.
class SupportDashboardScreen extends StatefulWidget {
  const SupportDashboardScreen({super.key});

  @override
  State<SupportDashboardScreen> createState() => _SupportDashboardScreenState();
}

class _SupportDashboardScreenState extends State<SupportDashboardScreen> {
  String? _selectedTicketId;
  // Ticker for SLA timer refresh — bumps every 30s so the queue items
  // re-evaluate their state without requiring user interaction.
  Timer? _slaTicker;
  int _slaTick = 0;

  @override
  void initState() {
    super.initState();
    // Seed canned responses on first load (no-op if already exist)
    CannedResponsesService.seedIfEmpty();
    _slaTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _slaTick++);
    });
  }

  @override
  void dispose() {
    _slaTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F9),
        appBar: _buildAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1100;
            if (!isWide) {
              // Narrow / mobile fallback — show only the queue, tap to drill in
              return _buildNarrowLayout();
            }
            return _buildWideLayout(constraints);
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // App bar
  // ─────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1A1A2E),
      elevation: 0.5,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: Color(0xFF6366F1), size: 22),
          ),
          const SizedBox(width: 12),
          const Text(
            'AnySkill Support',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Workspace',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10B981),
              ),
            ),
          ),
        ],
      ),
      actions: [
        // ── KPI pills (Phase 2) ────────────────────────────────────────────
        // Re-fetched whenever the SLA ticker fires (every 30s) so numbers
        // stay live without us needing a separate stream.
        FutureBuilder<({int closedToday, int openMine, int slaBreached, double? csat})>(
          key: ValueKey('kpi_$_slaTick'),
          future: SupportAgentService.myDailyKpi(),
          builder: (context, snap) {
            final k = snap.data;
            final csatLabel = (k?.csat ?? 0) == 0
                ? '—'
                : (k!.csat!).toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                children: [
                  _kpiPill(
                    icon: Icons.star_rounded,
                    label: csatLabel,
                    color: const Color(0xFFF59E0B),
                    tooltip: 'CSAT (24 שעות)',
                  ),
                  const SizedBox(width: 6),
                  _kpiPill(
                    icon: Icons.check_circle_rounded,
                    label: '${k?.closedToday ?? 0}',
                    color: const Color(0xFF10B981),
                    tooltip: 'נסגרו היום',
                  ),
                  const SizedBox(width: 6),
                  _kpiPill(
                    icon: Icons.inbox_rounded,
                    label: '${k?.openMine ?? 0}',
                    color: const Color(0xFF6366F1),
                    tooltip: 'פתוחות אצלי',
                  ),
                  const SizedBox(width: 6),
                  _kpiPill(
                    icon: Icons.local_fire_department_rounded,
                    label: '${k?.slaBreached ?? 0}',
                    color: (k?.slaBreached ?? 0) > 0
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6B7280),
                    tooltip: 'פיגורי SLA אצלי',
                  ),
                ],
              ),
            );
          },
        ),
        const VerticalDivider(width: 12, indent: 14, endIndent: 14),
        // ── Open queue counter ─────────────────────────────────────────────
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: SupportAgentService.streamOpenQueue(limit: 100),
          builder: (context, snap) {
            final count = snap.data?.length ?? 0;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _kpiPill(
                icon: Icons.list_alt_rounded,
                label: '$count פתוחות',
                color: const Color(0xFF6366F1),
                tooltip: 'תור כללי',
                wide: true,
              ),
            );
          },
        ),
        // ── Current agent + Switch Role ────────────────────────────────────
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid ?? '_')
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() as Map<String, dynamic>? ?? {};
            final name = data['name'] as String? ??
                FirebaseAuth.instance.currentUser?.email ??
                'Agent';
            final img = data['profileImage'] as String? ?? '';
            final roles = UserRoles.fromUserDoc(data);
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        const Color(0xFF6366F1).withValues(alpha: 0.12),
                    backgroundImage: safeImageProvider(img),
                    child: safeImageProvider(img) == null
                        ? Text(
                            name.isNotEmpty ? name[0] : '?',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366F1),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  if (roles.hasMultiple) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'החלף תפקיד',
                      icon: const Icon(Icons.swap_horiz_rounded,
                          size: 20, color: Color(0xFF8B5CF6)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const RoleSwitcherScreen(allowBack: true),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, size: 20),
          tooltip: 'התנתקות',
          onPressed: () => performSignOut(context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _kpiPill({
    required IconData icon,
    required String label,
    required Color color,
    required String tooltip,
    bool wide = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: wide ? 10 : 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Wide layout (≥1100px) — 3-pane split-screen
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWideLayout(BoxConstraints constraints) {
    return Row(
      children: [
        // ── Left: Ticket queue ────────────────────────────────────────────
        SizedBox(
          width: 300,
          child: TicketQueuePane(
            selectedTicketId: _selectedTicketId,
            onSelect: (id) => setState(() => _selectedTicketId = id),
            slaTick: _slaTick,
          ),
        ),
        const VerticalDivider(width: 1),
        // ── Center: Customer 360 + chat ───────────────────────────────────
        Expanded(
          child: _selectedTicketId == null
              ? const _EmptyWorkspaceState()
              : Customer360Pane(ticketId: _selectedTicketId!),
        ),
        const VerticalDivider(width: 1),
        // ── Right: Action Center ──────────────────────────────────────────
        SizedBox(
          width: 360,
          child: _selectedTicketId == null
              ? const SizedBox.shrink()
              : ActionCenterPane(ticketId: _selectedTicketId!),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Narrow layout (<1100px) — queue only, drill in to ticket
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNarrowLayout() {
    if (_selectedTicketId == null) {
      return TicketQueuePane(
        selectedTicketId: null,
        onSelect: (id) => setState(() => _selectedTicketId = id),
        slaTick: _slaTick,
      );
    }
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => setState(() => _selectedTicketId = null),
              ),
              const Text('חזרה לתור', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        Expanded(child: Customer360Pane(ticketId: _selectedTicketId!)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EmptyWorkspaceState — shown when no ticket is selected
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyWorkspaceState extends StatelessWidget {
  const _EmptyWorkspaceState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 64,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'בחר פנייה מהתור כדי להתחיל',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'הפניות הדחופות ביותר מסומנות באדום',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TicketQueuePane — left side (filters + ticket list with SLA timers)
// ═══════════════════════════════════════════════════════════════════════════

class TicketQueuePane extends StatefulWidget {
  final String? selectedTicketId;
  final void Function(String) onSelect;
  final int slaTick;

  const TicketQueuePane({
    super.key,
    required this.selectedTicketId,
    required this.onSelect,
    required this.slaTick,
  });

  @override
  State<TicketQueuePane> createState() => _TicketQueuePaneState();
}

class _TicketQueuePaneState extends State<TicketQueuePane> {
  String _filterAssignment = 'all'; // all | me | unassigned
  String? _filterPriority; // null = all priorities

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Text(
                  'תור פניות',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () => setState(() {}),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Assignment filter chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _filterChip('הכל', 'all', _filterAssignment, (v) {
                  setState(() => _filterAssignment = v);
                }),
                _filterChip('שלי', 'me', _filterAssignment, (v) {
                  setState(() => _filterAssignment = v);
                }),
                _filterChip('לא משויך', 'unassigned', _filterAssignment, (v) {
                  setState(() => _filterAssignment = v);
                }),
              ],
            ),
          ),
          // Priority chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _priorityChip('כל עדיפות', null),
                _priorityChip('🔴 דחוף', 'urgent'),
                _priorityChip('🟠 גבוה', 'high'),
                _priorityChip('🟡 רגיל', 'normal'),
                _priorityChip('🟢 נמוך', 'low'),
              ],
            ),
          ),
          const Divider(height: 1),
          // Queue list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupportAgentService.streamOpenQueue(
                assignedToFilter:
                    _filterAssignment == 'all' ? null : _filterAssignment,
                filterPriority: _filterPriority,
              ),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final tickets = snap.data!;
                // Phase 2 — banners over the queue list.
                final breachedCount = tickets
                    .where((t) =>
                        SupportAgentService.slaStateFor(t) == 'breached')
                    .length;
                final proactiveCount = tickets
                    .where((t) => t['type'] == 'proactive')
                    .length;
                final banners = <Widget>[
                  // Smart Routing — informational, always shown
                  _queueBanner(
                    icon: Icons.route_rounded,
                    label: 'ניתוב חכם פעיל — פניות מנותבות לפי קטגוריה ועומס',
                    color: const Color(0xFF8B5CF6),
                  ),
                  if (proactiveCount > 0)
                    _queueBanner(
                      icon: Icons.bolt_rounded,
                      label: '⚡ $proactiveCount פניות נפתחו אוטומטית',
                      color: const Color(0xFF10B981),
                    ),
                  if (breachedCount > 0)
                    _queueBanner(
                      icon: Icons.warning_amber_rounded,
                      label: '🔴 $breachedCount פניות בפיגור SLA',
                      color: const Color(0xFFEF4444),
                    ),
                ];
                if (tickets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text('אין פניות פתוחות',
                              style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  );
                }

                // Sort: breached SLA first, then warning, then on_track
                tickets.sort((a, b) {
                  final order = {'breached': 0, 'warning': 1, 'on_track': 2};
                  final aOrder =
                      order[SupportAgentService.slaStateFor(a)] ?? 2;
                  final bOrder =
                      order[SupportAgentService.slaStateFor(b)] ?? 2;
                  if (aOrder != bOrder) return aOrder.compareTo(bOrder);
                  // Then by createdAt desc
                  final at = (a['createdAt'] as Timestamp?)?.toDate();
                  final bt = (b['createdAt'] as Timestamp?)?.toDate();
                  if (at == null || bt == null) return 0;
                  return bt.compareTo(at);
                });

                return Column(
                  children: [
                    if (banners.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Column(children: banners),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: tickets.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (_, i) => _TicketCard(
                          ticket: tickets[i],
                          isSelected: tickets[i]['ticketId'] ==
                              widget.selectedTicketId,
                          onTap: () =>
                              widget.onSelect(tickets[i]['ticketId']),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueBanner({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    String value,
    String selected,
    void Function(String) onTap,
  ) {
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (_) => onTap(value),
        selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF6366F1) : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF6366F1)
              : Colors.grey.shade300,
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _priorityChip(String label, String? value) {
    final isSelected = _filterPriority == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (_) => setState(() => _filterPriority = value),
        selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFFD97706) : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFFD97706)
              : Colors.grey.shade300,
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ── Individual ticket card in the queue ────────────────────────────────────

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final bool isSelected;
  final VoidCallback onTap;

  const _TicketCard({
    required this.ticket,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ticketId = ticket['ticketId'] as String;
    final userName = ticket['userName'] as String? ?? 'משתמש';
    final subject = ticket['subject'] as String? ?? '';
    final priority = ticket['priority'] as String? ?? 'normal';
    final assignedTo = ticket['assignedTo'] as String?;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = assignedTo != null && assignedTo == myUid;

    final slaState = SupportAgentService.slaStateFor(ticket);
    final age = SupportAgentService.formatTicketAge(ticket);

    final (slaColor, slaBg) = switch (slaState) {
      'breached' => (const Color(0xFFEF4444), const Color(0xFFFEE2E2)),
      'warning' => (const Color(0xFFF59E0B), const Color(0xFFFEF3C7)),
      _ => (const Color(0xFF10B981), const Color(0xFFD1FAE5)),
    };

    return Material(
      color: isSelected
          ? const Color(0xFF6366F1).withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: SLA pill + name + priority dot
              Row(
                children: [
                  // SLA timer pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: slaBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: slaColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          age,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: slaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isMine)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: 6),
                      child: Icon(Icons.person_pin_circle_rounded,
                          size: 14, color: Color(0xFF6366F1)),
                    ),
                  // Priority indicator
                  if (priority == 'urgent')
                    const Text('🔴', style: TextStyle(fontSize: 10))
                  else if (priority == 'high')
                    const Text('🟠', style: TextStyle(fontSize: 10))
                  else if (priority == 'low')
                    const Text('🟢', style: TextStyle(fontSize: 10)),
                  const Spacer(),
                  Text(
                    '#${ticketId.substring(0, 6)}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF9CA3AF),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // User name
              Text(
                userName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF1A1A2E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              // Subject preview
              Text(
                subject,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Customer360Pane — center pane (chat + customer info bar)
// ═══════════════════════════════════════════════════════════════════════════

class Customer360Pane extends StatefulWidget {
  final String ticketId;
  const Customer360Pane({super.key, required this.ticketId});

  @override
  State<Customer360Pane> createState() => _Customer360PaneState();
}

class _Customer360PaneState extends State<Customer360Pane> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  // Phase 2: 3-party chat channels — 'customer' | 'provider' | 'internal'.
  String _activeChannel = SupportAgentService.channelCustomer;
  // Track last-seen message count per-channel so we only auto-scroll when
  // a NEW message arrives on the visible channel.
  int _lastMessageCount = 0;
  // Phase 2 — slash-shortcut autocomplete state.
  List<Map<String, dynamic>> _allCannedTemplates = const [];
  String _shortcutQuery = '';

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(_onComposerChanged);
    // Eagerly cache templates so /shortcut autocomplete is instant.
    CannedResponsesService.streamAll().first.then((t) {
      if (mounted) setState(() => _allCannedTemplates = t);
    }).catchError((_) {});
  }

  void _onComposerChanged() {
    final raw = _msgCtrl.text;
    // Show suggestions ONLY when the buffer is exactly a single token
    // beginning with '/' — typing further tokens after a real message
    // shouldn't pop the picker.
    final trimmed = raw.trimLeft();
    final isShortcut =
        trimmed.startsWith('/') && !trimmed.contains(' ') && !trimmed.contains('\n');
    final next = isShortcut ? trimmed : '';
    if (next != _shortcutQuery) {
      setState(() => _shortcutQuery = next);
    }
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onComposerChanged);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      final agentName = FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email ??
          'תמיכה';
      await SupportAgentService.sendMessage(
        ticketId: widget.ticketId,
        message: text,
        agentName: agentName,
        channel: _activeChannel,
      );
      // After sending an internal note, slide back to the customer channel
      // so the agent doesn't accidentally send a follow-up as internal.
      if (_activeChannel == SupportAgentService.channelInternal && mounted) {
        setState(() => _activeChannel = SupportAgentService.channelCustomer);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאת שליחה: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showCannedResponses() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: CannedResponsesService.streamAll(),
          builder: (context, snap) {
            final templates = snap.data ?? [];
            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'תבניות תשובה',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: templates.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          itemCount: templates.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final t = templates[i];
                            return ListTile(
                              title: Text(
                                t['title'] as String? ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  t['body'] as String? ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              onTap: () => _insertTemplate(t),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _insertTemplate(Map<String, dynamic> template) async {
    // Need customer name to fill placeholder
    final ticketSnap = await FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(widget.ticketId)
        .get();
    final t = ticketSnap.data() ?? {};
    final customerName = t['userName'] as String? ?? 'לקוח';
    final agentName = FirebaseAuth.instance.currentUser?.displayName ??
        FirebaseAuth.instance.currentUser?.email ??
        'תמיכה';
    final filled = CannedResponsesService.fillPlaceholders(
      template['body'] as String? ?? '',
      customerName: customerName,
      ticketId: widget.ticketId,
      agentName: agentName,
    );
    if (mounted) {
      _msgCtrl.text = filled;
      _msgCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _msgCtrl.text.length),
      );
      // Pop only if we're inside a modal (the bottom-sheet picker). The
      // inline /shortcut autocomplete invokes us with a non-modal context
      // so canPop is false there — skip.
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: SupportAgentService.watchTicket(widget.ticketId),
      builder: (context, ticketSnap) {
        final ticket = ticketSnap.data;
        if (ticket == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            // ── Customer info bar (top of center pane) ────────────────────
            _buildCustomerInfoBar(ticket),
            const Divider(height: 1),
            // ── Messages list ─────────────────────────────────────────────
            Expanded(child: _buildMessagesList()),
            // ── Composer ──────────────────────────────────────────────────
            _buildComposer(ticket),
          ],
        );
      },
    );
  }

  Widget _buildCustomerInfoBar(Map<String, dynamic> ticket) {
    final userName = ticket['userName'] as String? ?? 'משתמש';
    final subject = ticket['subject'] as String? ?? '';
    final status = ticket['status'] as String? ?? 'open';
    final priority = ticket['priority'] as String? ?? 'normal';
    final assignedTo = ticket['assignedTo'] as String?;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = assignedTo != null && assignedTo == myUid;
    final canTake = assignedTo == null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statusChip(status),
                    const SizedBox(width: 6),
                    _priorityChip(priority),
                    if (isMine) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_pin_circle_rounded,
                                size: 11, color: Color(0xFF6366F1)),
                            SizedBox(width: 3),
                            Text(
                              'אצלי',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subject,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Claim button (if unassigned)
          if (canTake)
            ElevatedButton.icon(
              icon: const Icon(Icons.flag_rounded, size: 16),
              label: const Text('קח לטיפול'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
              onPressed: () async {
                final agentName =
                    FirebaseAuth.instance.currentUser?.displayName ??
                        FirebaseAuth.instance.currentUser?.email ??
                        'תמיכה';
                try {
                  await SupportAgentService.claimTicket(
                    ticketId: widget.ticketId,
                    agentName: agentName,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('שגיאה: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  // ── Channel helpers (Phase 2) ──────────────────────────────────────────
  Color _channelAccent() {
    switch (_activeChannel) {
      case SupportAgentService.channelProvider:
        return const Color(0xFF10B981);
      case SupportAgentService.channelInternal:
        return const Color(0xFFF59E0B);
      case SupportAgentService.channelCustomer:
      default:
        return const Color(0xFF6366F1);
    }
  }

  Color _composerBg() {
    switch (_activeChannel) {
      case SupportAgentService.channelProvider:
        return const Color(0xFFECFDF5);
      case SupportAgentService.channelInternal:
        return const Color(0xFFFEF3C7);
      case SupportAgentService.channelCustomer:
      default:
        return Colors.grey[50]!;
    }
  }

  String _composerHint() {
    switch (_activeChannel) {
      case SupportAgentService.channelProvider:
        return 'הודעה לנותן השירות (הלקוח לא רואה)';
      case SupportAgentService.channelInternal:
        return 'הערה פנימית — לאף אחד מהצדדים אין גישה';
      case SupportAgentService.channelCustomer:
      default:
        return 'כתוב תשובה ללקוח...';
    }
  }

  Widget _channelChip({
    required String label,
    required String channel,
    required Color accent,
    bool disabled = false,
    String? disabledTooltip,
  }) {
    final selected = _activeChannel == channel;
    final chip = ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: disabled
          ? null
          : (_) => setState(() => _activeChannel = channel),
      selectedColor: accent.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: disabled
            ? Colors.grey[400]
            : (selected ? accent : Colors.grey[600]),
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (disabled && disabledTooltip != null) {
      return Tooltip(message: disabledTooltip, child: chip);
    }
    return chip;
  }

  Widget _buildMessagesList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupportAgentService.streamMessages(
        widget.ticketId,
        channelFilter: _activeChannel,
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snap.data!;
        // Auto-scroll to bottom ONLY when the message count actually grew —
        // otherwise every unrelated rebuild would schedule a jumpTo, racing
        // with in-progress scroll gestures and occasionally triggering
        // "setState during build" when ScrollController listeners fire.
        if (messages.length != _lastMessageCount) {
          _lastMessageCount = messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              if (_scrollCtrl.hasClients &&
                  _scrollCtrl.position.hasContentDimensions) {
                _scrollCtrl
                    .jumpTo(_scrollCtrl.position.maxScrollExtent);
              }
            } catch (_) {
              // Ignore — viewport not laid out yet.
            }
          });
        }
        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (_, i) {
            final m = messages[i];
            final isAgent = m['isAdmin'] == true;
            final isInternal = m['isInternal'] == true;
            final text = m['message'] as String? ?? '';
            final senderName = m['senderName'] as String? ?? '';
            final ts = (m['createdAt'] as Timestamp?)?.toDate();

            // Internal note styling
            if (isInternal) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'הערה פנימית · $senderName',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            text,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ts != null)
                      Text(
                        DateFormat('HH:mm').format(ts),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFD97706),
                        ),
                      ),
                  ],
                ),
              );
            }

            // Public messages — bubble layout
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment:
                    isAgent ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAgent
                            ? const Color(0xFF6366F1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: isAgent
                            ? null
                            : Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: TextStyle(
                              fontSize: 13,
                              color: isAgent
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              height: 1.5,
                            ),
                          ),
                          if (ts != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('HH:mm').format(ts),
                              style: TextStyle(
                                fontSize: 10,
                                color: isAgent
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShortcutAutocomplete() {
    final matches = CannedResponsesService.filterByShortcut(
      _allCannedTemplates,
      _shortcutQuery,
    ).take(6).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: matches.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final t = matches[i];
          final shortcut = CannedResponsesService.shortcutFor(t);
          final title = t['title'] as String? ?? '';
          final body = t['body'] as String? ?? '';
          return InkWell(
            onTap: () => _insertTemplate(t),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      shortcut,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
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

  Widget _buildComposer(Map<String, dynamic> ticket) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // Phase 2 — slash-shortcut autocomplete dropdown
          if (_shortcutQuery.isNotEmpty) _buildShortcutAutocomplete(),
          // Phase 2 — 3-channel toggle: customer / provider / internal note.
          // Provider chip is disabled when the ticket has no providerId.
          Builder(builder: (_) {
            final providerId = (ticket['providerId'] as String?) ?? '';
            final hasProvider = providerId.isNotEmpty;
            return Row(
              children: [
                _channelChip(
                  label: '💬 ללקוח',
                  channel: SupportAgentService.channelCustomer,
                  accent: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 6),
                _channelChip(
                  label: '🛠️ לנותן שירות',
                  channel: SupportAgentService.channelProvider,
                  accent: const Color(0xFF10B981),
                  disabled: !hasProvider,
                  disabledTooltip: 'אין נותן שירות משויך לפנייה',
                ),
                const SizedBox(width: 6),
                _channelChip(
                  label: '🔒 הערה פנימית',
                  channel: SupportAgentService.channelInternal,
                  accent: const Color(0xFFD97706),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showCannedResponses,
                  icon: const Icon(Icons.shortcut_rounded, size: 14),
                  label: const Text('תבניות', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 6),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _composerBg(),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _channelAccent().withValues(alpha: 0.35),
                    ),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: _composerHint(),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: _channelAccent(),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(14),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                onPressed: _sending ? null : _send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'open' => ('פתוח', const Color(0xFFF59E0B)),
      'in_progress' => ('בטיפול', const Color(0xFF6366F1)),
      'resolved' => ('נפתר', const Color(0xFF10B981)),
      'closed' => ('סגור', const Color(0xFF6B7280)),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _priorityChip(String priority) {
    final (label, color) = switch (priority) {
      'urgent' => ('🔴 דחוף', const Color(0xFFEF4444)),
      'high' => ('🟠 גבוה', const Color(0xFFF59E0B)),
      'low' => ('🟢 נמוך', const Color(0xFF10B981)),
      _ => ('🟡 רגיל', const Color(0xFF6366F1)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ActionCenterPane — right side (customer context + agent actions)
// ═══════════════════════════════════════════════════════════════════════════

class ActionCenterPane extends StatefulWidget {
  final String ticketId;
  const ActionCenterPane({super.key, required this.ticketId});

  @override
  State<ActionCenterPane> createState() => _ActionCenterPaneState();
}

class _ActionCenterPaneState extends State<ActionCenterPane> {
  Map<String, dynamic>? _customer360;
  bool _loading = true;
  String? _customerUserId;
  // Phase 2 — lazy-loaded right-pane tab data.
  Map<String, dynamic>? _ticketCache;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _jobData;
  bool _providerLoading = false;
  bool _jobLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCustomer360();
  }

  @override
  void didUpdateWidget(ActionCenterPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketId != widget.ticketId) {
      // Defer to post-frame — calling setState synchronously from
      // didUpdateWidget runs during the element tree reconciliation phase
      // and can race with ancestor rebuilds, producing "setState during
      // build" in strict mode.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCustomer360();
      });
    }
  }

  Future<void> _loadCustomer360() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _customer360 = null;
      _providerProfile = null;
      _jobData = null;
    });
    try {
      final ticketSnap = await FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(widget.ticketId)
          .get();
      final ticketData = ticketSnap.data() ?? {};
      _ticketCache = ticketData;
      final userId = ticketData['userId'] as String? ?? '';
      _customerUserId = userId;
      if (userId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data =
          await SupportAgentService.loadCustomer360(customerUserId: userId);
      if (mounted) {
        setState(() {
          _customer360 = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Phase 2 — lazy load the provider profile when the Provider tab opens.
  Future<void> _ensureProviderLoaded() async {
    if (_providerProfile != null || _providerLoading) return;
    final providerId = (_ticketCache?['providerId'] as String?) ?? '';
    if (providerId.isEmpty) return;
    setState(() => _providerLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(providerId)
          .get();
      if (mounted) {
        setState(() {
          _providerProfile = snap.data() ?? {};
          _providerLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _providerLoading = false);
    }
  }

  /// Phase 2 — lazy load the linked job when the Order tab opens.
  Future<void> _ensureJobLoaded() async {
    if (_jobData != null || _jobLoading) return;
    final jobId = (_ticketCache?['jobId'] as String?) ?? '';
    if (jobId.isEmpty) return;
    setState(() => _jobLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobId)
          .get();
      if (mounted) {
        setState(() {
          _jobData = snap.data() ?? {};
          _jobLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _jobLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customer360 == null || _customerUserId == null) {
      return const Center(child: Text('לא ניתן לטעון פרטי לקוח'));
    }

    final hasProvider =
        ((_ticketCache?['providerId'] as String?) ?? '').isNotEmpty;
    final hasJob = ((_ticketCache?['jobId'] as String?) ?? '').isNotEmpty;

    return Container(
      color: Colors.white,
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            Material(
              color: Colors.white,
              elevation: 0.5,
              child: TabBar(
                onTap: (i) {
                  if (i == 1) _ensureProviderLoaded();
                  if (i == 2) _ensureJobLoaded();
                },
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: const Color(0xFF6B7280),
                indicatorColor: const Color(0xFF6366F1),
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
                tabs: [
                  const Tab(text: '👤 לקוח'),
                  Tab(text: '🛠️ נותן שירות${hasProvider ? '' : ' —'}'),
                  Tab(text: '📦 הזמנה${hasJob ? '' : ' —'}'),
                  const Tab(text: '🤖 בוט/AI'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildCustomerTabBody(),
                  _buildProviderTabBody(hasProvider),
                  _buildOrderTabBody(hasJob),
                  _buildBotTabBody(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 2 — TAB BODIES
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCustomerTabBody() {
    final profile =
        _customer360!['profile'] as Map<String, dynamic>? ?? {};
    final recentJobs =
        _customer360!['recentJobs'] as List<dynamic>? ?? [];
    final recentTransactions =
        _customer360!['recentTransactions'] as List<dynamic>? ?? [];
    final openTicketsCount =
        _customer360!['openTicketsCount'] as int? ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            // ── Section: Customer profile card ────────────────────────────
            _buildProfileCard(profile, openTicketsCount),
            const SizedBox(height: 16),

            // ── Section: Action buttons ───────────────────────────────────
            _sectionHeader('🛠️ פעולות'),
            _actionButton(
              icon: Icons.verified_user_rounded,
              label: 'אמת זהות',
              color: const Color(0xFF10B981),
              onTap: () => _confirmAction(
                title: 'אימות זהות',
                action: 'verify_identity',
                confirmText:
                    'האם לאמת את הזהות של ${profile['name'] ?? "הלקוח"}?',
              ),
            ),
            _actionButton(
              icon: Icons.lock_reset_rounded,
              label: 'איפוס סיסמה (שלח מייל)',
              color: const Color(0xFF6366F1),
              onTap: () => _confirmAction(
                title: 'איפוס סיסמה',
                action: 'send_password_reset',
                confirmText:
                    'האם לשלוח מייל איפוס סיסמה ל-${profile['email'] ?? "הלקוח"}?',
              ),
            ),
            _actionButton(
              icon: Icons.flag_rounded,
              label: profile['flagged'] == true
                  ? 'הסר דגל מהחשבון'
                  : 'דגל את החשבון',
              color: profile['flagged'] == true
                  ? const Color(0xFF6B7280)
                  : const Color(0xFFEF4444),
              onTap: () => _confirmAction(
                title: profile['flagged'] == true
                    ? 'הסרת דגל'
                    : 'דגל את החשבון',
                action: profile['flagged'] == true
                    ? 'unflag_account'
                    : 'flag_account',
                confirmText: profile['flagged'] == true
                    ? 'להסיר את הדגל מהחשבון?'
                    : 'לדגל את החשבון לבדיקה?',
                requireReason: true,
              ),
            ),
            const SizedBox(height: 16),

            // ── Section: Resolution buttons ───────────────────────────────
            _sectionHeader('🎯 סיום פנייה'),
            _actionButton(
              icon: Icons.check_circle_outline_rounded,
              label: 'סמן כנפתר וסגור',
              color: const Color(0xFF10B981),
              onTap: _closeTicket,
            ),
            const SizedBox(height: 16),

            // ── Section: Customer context ─────────────────────────────────
            _sectionHeader('📊 הקשר'),
            _statRow(
                'הזמנות אחרונות', '${recentJobs.length}', Icons.work_outline),
            _statRow(
              'יתרה',
              '₪${(profile['balance'] as num? ?? 0).toStringAsFixed(0)}',
              Icons.account_balance_wallet_outlined,
            ),
            _statRow(
              'דירוג',
              '⭐ ${(profile['rating'] as num? ?? 0).toStringAsFixed(1)}',
              Icons.star_outline_rounded,
            ),
            _statRow(
              'עסקאות',
              '${recentTransactions.length}',
              Icons.receipt_long_outlined,
            ),
            if (openTicketsCount > 1)
              _statRow(
                'פניות פתוחות',
                '$openTicketsCount',
                Icons.support_outlined,
                highlight: true,
              ),

            const SizedBox(height: 16),

            // ── Section: Recent jobs ──────────────────────────────────────
            if (recentJobs.isNotEmpty) ...[
              _sectionHeader('📋 הזמנות אחרונות'),
              ...recentJobs.take(5).map((j) => _miniJobRow(j as Map<String, dynamic>)),
              const SizedBox(height: 16),
            ],

            // ── Section: Refresh ──────────────────────────────────────────
            TextButton.icon(
              onPressed: _loadCustomer360,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('רענן פרטים'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
    );
  }

  // ── Provider tab body ────────────────────────────────────────────────────
  Widget _buildProviderTabBody(bool hasProvider) {
    if (!hasProvider) {
      return _emptyTabState(
        icon: Icons.handyman_outlined,
        title: 'אין נותן שירות משויך לפנייה',
        subtitle: 'הוסף providerId על מסמך הפנייה כדי להציג כאן פרופיל ספק.',
      );
    }
    if (_providerLoading || _providerProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _providerProfile!;
    final name = p['name'] as String? ?? 'נותן שירות';
    final phone = p['phone'] as String? ?? '';
    final email = p['email'] as String? ?? '';
    final category = p['serviceType'] as String? ?? '';
    final rating = (p['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewsCount = (p['reviewsCount'] as num?)?.toInt() ?? 0;
    final orderCount = (p['orderCount'] as num?)?.toInt() ?? 0;
    final isVerified = p['isVerified'] == true;
    final isOnline = p['isOnline'] == true;
    final img = p['profileImage'] as String? ?? '';
    final trust = p['trustScore'] as num?;
    final cancelRate = (p['cancellationRate'] as num?)?.toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        const Color(0xFF10B981).withValues(alpha: 0.15),
                    backgroundImage: safeImageProvider(img),
                    child: safeImageProvider(img) == null
                        ? Text(
                            name.isNotEmpty ? name[0] : '?',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          )
                        : null,
                  ),
                  if (isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              size: 14, color: Color(0xFF10B981)),
                        ],
                      ],
                    ),
                    if (category.isNotEmpty)
                      Text(category,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TrustScoreBar(score: trust, title: 'אמינות נותן שירות'),
          const SizedBox(height: 16),
          _sectionHeader('📊 נתונים'),
          _statRow('הזמנות שהושלמו', '$orderCount', Icons.work_outline),
          _statRow('דירוג', '⭐ ${rating.toStringAsFixed(1)} ($reviewsCount)',
              Icons.star_outline_rounded),
          if (cancelRate != null)
            _statRow(
              'ביטולים',
              '${(cancelRate * 100).toStringAsFixed(0)}%',
              Icons.cancel_outlined,
              highlight: cancelRate > 0.10,
            ),
          if (phone.isNotEmpty) _profileRow(Icons.phone_rounded, phone),
          if (email.isNotEmpty) _profileRow(Icons.email_rounded, email),
        ],
      ),
    );
  }

  // ── Order tab body ───────────────────────────────────────────────────────
  Widget _buildOrderTabBody(bool hasJob) {
    if (!hasJob) {
      return _emptyTabState(
        icon: Icons.receipt_long_outlined,
        title: 'אין הזמנה משויכת לפנייה',
        subtitle: 'פניות ללא jobId הן בקשות תמיכה כלליות.',
      );
    }
    if (_jobLoading || _jobData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final j = _jobData!;
    final id = (_ticketCache?['jobId'] as String?) ?? '';
    final status = j['status'] as String? ?? '—';
    final category = j['category'] as String? ?? '—';
    final amount = (j['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final scheduled = (j['appointmentDate'] as Timestamp?)?.toDate();
    final created = (j['createdAt'] as Timestamp?)?.toDate();
    final address = j['address'] as String? ?? j['location'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 16, color: Color(0xFF6366F1)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        id,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(category,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionHeader('📋 פרטי הזמנה'),
          _statRow('סטטוס', status, Icons.flag_outlined),
          _statRow('סכום', '₪${amount.toStringAsFixed(0)}',
              Icons.attach_money_rounded),
          if (created != null)
            _statRow(
              'נוצרה',
              DateFormat('dd/MM/yy HH:mm').format(created),
              Icons.event_note_outlined,
            ),
          if (scheduled != null)
            _statRow(
              'מועד שירות',
              DateFormat('dd/MM/yy HH:mm').format(scheduled),
              Icons.schedule_rounded,
            ),
          if (address.isNotEmpty)
            _statRow('כתובת', address, Icons.location_on_outlined),
        ],
      ),
    );
  }

  // ── Bot/AI tab body — placeholder until Phase 5 ─────────────────────────
  Widget _buildBotTabBody() {
    final isBotEsc = _ticketCache?['type'] == 'bot_escalation';
    final intent = _ticketCache?['botIntent'] as String?;
    final steps = (_ticketCache?['botSteps'] as num?)?.toInt() ?? 0;

    final today = DateTime.now().toUtc();
    final dateKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Per-ticket bot context ──────────────────────────────────────
          if (isBotEsc)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.smart_toy_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'הופנה מהבוט',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (intent != null)
                    Row(
                      children: [
                        const Text(
                          'Intent זוהה: ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            intent,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '$steps צעדים בבוט לפני העברה',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'התכתובת המלאה עם הבוט נשמרה כהערה פנימית בערוץ "פנימי".',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'הפנייה הזו לא הופנתה מהבוט.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // ── Daily bot analytics ─────────────────────────────────────────
          const Text(
            'ביצועי הבוט היום',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .doc('bot_analytics/$dateKey')
                .snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? const <String, dynamic>{};
              final sessions = (data['sessions'] as num?)?.toInt() ?? 0;
              final auto = (data['autoResolved'] as num?)?.toInt() ?? 0;
              final handoffs = (data['handoffs'] as num?)?.toInt() ?? 0;
              final resolutionRate = sessions > 0
                  ? '${((auto / sessions) * 100).round()}%'
                  : '—';
              return Row(
                children: [
                  _botMiniStat(
                      '$sessions', 'שיחות', const Color(0xFF6366F1)),
                  const SizedBox(width: 6),
                  _botMiniStat(
                      '$auto', 'נפתרו ע"י הבוט', const Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  _botMiniStat(
                      '$handoffs', 'הועברו', const Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  _botMiniStat(
                      resolutionRate, 'אחוז פתרון', const Color(0xFF8B5CF6)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _botMiniStat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.85),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTabState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: const Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> profile, int openTickets) {
    final name = profile['name'] as String? ?? 'משתמש';
    final email = profile['email'] as String? ?? '';
    final phone = profile['phone'] as String? ?? '';
    final img = profile['profileImage'] as String? ?? '';
    final isFlagged = profile['flagged'] == true;
    final isProvider = profile['isProvider'] == true;
    final isVerified = profile['isVerified'] == true;
    final createdAt = profile['createdAt'] as Timestamp?;
    final memberSince = createdAt != null
        ? '${DateTime.now().difference(createdAt.toDate()).inDays} ימים'
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F9),
        borderRadius: BorderRadius.circular(14),
        border: isFlagged
            ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    const Color(0xFF6366F1).withValues(alpha: 0.12),
                backgroundImage: safeImageProvider(img),
                child: safeImageProvider(img) == null
                    ? Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              size: 14, color: Color(0xFF10B981)),
                        ],
                        if (isFlagged) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.flag_rounded,
                              size: 14, color: Color(0xFFEF4444)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isProvider ? 'נותן שירות' : 'לקוח',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (email.isNotEmpty)
            _profileRow(Icons.email_outlined, email),
          if (phone.isNotEmpty)
            _profileRow(Icons.phone_outlined, phone),
          _profileRow(Icons.calendar_today_outlined, 'חבר $memberSince'),
          const SizedBox(height: 12),
          TrustScoreBar(
            score: profile['trustScore'] as num?,
            title: 'אמינות לקוח',
          ),
        ],
      ),
    );
  }

  Widget _profileRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 42),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: AlignmentDirectional.centerStart,
        ),
      ),
    );
  }

  Widget _statRow(
    String label,
    String value,
    IconData icon, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: highlight
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniJobRow(Map<String, dynamic> job) {
    final amount = (job['totalAmount'] as num? ?? 0).toDouble();
    final status = job['status'] as String? ?? '';
    final createdAt = (job['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null
        ? DateFormat('dd/MM').format(createdAt)
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: status == 'completed'
                  ? const Color(0xFF10B981)
                  : status == 'cancelled'
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₪${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$dateStr · $status',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action confirmation flow ──────────────────────────────────────────────

  Future<void> _confirmAction({
    required String title,
    required String action,
    required String confirmText,
    bool requireReason = false,
  }) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(confirmText),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: requireReason
                    ? 'סיבה (חובה — מינ\' 5 תווים)'
                    : 'סיבה / הקשר',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              if (requireReason && reasonCtrl.text.trim().length < 5) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('סיבה חייבת להכיל לפחות 5 תווים')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('אשר'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = reasonCtrl.text.trim().isEmpty
        ? 'פעולה דרך $title מהדשבורד'
        : reasonCtrl.text.trim();

    try {
      switch (action) {
        case 'verify_identity':
          await SupportAgentService.verifyIdentity(
            targetUserId: _customerUserId!,
            reason: reason,
            ticketId: widget.ticketId,
          );
          break;
        case 'send_password_reset':
          await SupportAgentService.sendPasswordReset(
            targetUserId: _customerUserId!,
            reason: reason,
            ticketId: widget.ticketId,
          );
          break;
        case 'flag_account':
          await SupportAgentService.flagAccount(
            targetUserId: _customerUserId!,
            reason: reason,
            ticketId: widget.ticketId,
          );
          break;
        case 'unflag_account':
          await SupportAgentService.unflagAccount(
            targetUserId: _customerUserId!,
            reason: reason,
            ticketId: widget.ticketId,
          );
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $title הושלם'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        await _loadCustomer360();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _closeTicket() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('סגור פנייה'),
        content: const Text(
          'הפנייה תסומן כסגורה והלקוח יקבל בקשה לדרג את השירות. להמשיך?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SupportAgentService.closeTicket(
        ticketId: widget.ticketId,
        customerUserId: _customerUserId!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ פנייה נסגרה. הלקוח קיבל בקשת דירוג.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
