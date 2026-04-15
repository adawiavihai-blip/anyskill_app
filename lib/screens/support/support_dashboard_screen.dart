// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/auth_service.dart';
import '../../services/canned_responses_service.dart';
import '../../services/support_agent_service.dart';
import '../../utils/safe_image_provider.dart';

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
        // Open queue counter — quick visual cue
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: SupportAgentService.streamOpenQueue(limit: 100),
          builder: (context, snap) {
            final count = snap.data?.length ?? 0;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '$count פתוחות',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            );
          },
        ),
        // Current agent name
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
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
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

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) => _TicketCard(
                    ticket: tickets[i],
                    isSelected:
                        tickets[i]['ticketId'] == widget.selectedTicketId,
                    onTap: () => widget.onSelect(tickets[i]['ticketId']),
                  ),
                );
              },
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
  bool _internalMode = false; // toggle for internal note vs public reply
  // Track last-seen message count so we only auto-scroll when a NEW message
  // arrives — not on every unrelated rebuild (typing, mode toggle, etc.)
  int _lastMessageCount = 0;

  @override
  void dispose() {
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
        isInternal: _internalMode,
      );
      // Reset internal mode after sending so the agent doesn't accidentally
      // send the next message as internal
      if (_internalMode) {
        setState(() => _internalMode = false);
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
      Navigator.of(context).pop();
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

  Widget _buildMessagesList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupportAgentService.streamMessages(widget.ticketId),
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

  Widget _buildComposer(Map<String, dynamic> ticket) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // Mode toggle: public / internal note
          Row(
            children: [
              ChoiceChip(
                label: const Text('💬 הודעה ללקוח',
                    style: TextStyle(fontSize: 11)),
                selected: !_internalMode,
                onSelected: (_) => setState(() => _internalMode = false),
                selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: !_internalMode
                      ? const Color(0xFF6366F1)
                      : Colors.grey[600],
                  fontWeight: !_internalMode
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('🔒 הערה פנימית',
                    style: TextStyle(fontSize: 11)),
                selected: _internalMode,
                onSelected: (_) => setState(() => _internalMode = true),
                selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: _internalMode
                      ? const Color(0xFFD97706)
                      : Colors.grey[600],
                  fontWeight: _internalMode
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          ),
          const SizedBox(height: 6),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _internalMode
                        ? const Color(0xFFFEF3C7)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _internalMode
                          ? const Color(0xFFF59E0B)
                              .withValues(alpha: 0.4)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: _internalMode
                          ? 'הערה פנימית — לקוח לא רואה את זה'
                          : 'כתוב תשובה ללקוח...',
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
                  backgroundColor: _internalMode
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF6366F1),
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
    });
    try {
      final ticketSnap = await FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(widget.ticketId)
          .get();
      final ticketData = ticketSnap.data() ?? {};
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customer360 == null || _customerUserId == null) {
      return const Center(child: Text('לא ניתן לטעון פרטי לקוח'));
    }

    final profile =
        _customer360!['profile'] as Map<String, dynamic>? ?? {};
    final recentJobs =
        _customer360!['recentJobs'] as List<dynamic>? ?? [];
    final recentTransactions =
        _customer360!['recentTransactions'] as List<dynamic>? ?? [];
    final openTicketsCount =
        _customer360!['openTicketsCount'] as int? ?? 0;

    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
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
