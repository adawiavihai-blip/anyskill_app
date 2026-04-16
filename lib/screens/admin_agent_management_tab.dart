// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/support_agent_service.dart';
import '../utils/safe_image_provider.dart';

/// Admin tab — manage Support Agents.
///
/// The admin can:
///   • See all current support_agents
///   • Promote any user to support_agent
///   • Demote a support_agent back to regular user
///   • View the recent support_audit_log entries (who did what)
///
/// Role changes go through the setUserRole CF, which writes to both
/// admin_audit_log AND support_audit_log so the change is permanently
/// traceable.
class AdminAgentManagementTab extends StatefulWidget {
  const AdminAgentManagementTab({super.key});

  @override
  State<AdminAgentManagementTab> createState() =>
      _AdminAgentManagementTabState();
}

class _AdminAgentManagementTabState extends State<AdminAgentManagementTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Column(
              children: [
                // Migration banner (Phase 1 multi-role rollout)
                const _RoleMigrationBanner(),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: const Color(0xFF6366F1),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF6366F1),
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(icon: Icon(Icons.support_agent_rounded, size: 20),
                        text: 'סוכנים'),
                    Tab(icon: Icon(Icons.schedule_rounded, size: 20),
                        text: 'משמרות'),
                    Tab(icon: Icon(Icons.trending_up_rounded, size: 20),
                        text: 'KPI'),
                    Tab(icon: Icon(Icons.warning_amber_rounded, size: 20),
                        text: 'הסלמה'),
                    Tab(icon: Icon(Icons.route_rounded, size: 20),
                        text: 'ניתוב'),
                    Tab(icon: Icon(Icons.shortcut_rounded, size: 20),
                        text: 'תבניות'),
                    Tab(icon: Icon(Icons.smart_toy_rounded, size: 20),
                        text: 'בוט'),
                    Tab(icon: Icon(Icons.bolt_rounded, size: 20),
                        text: 'Proactive'),
                    Tab(icon: Icon(Icons.history_rounded, size: 20),
                        text: 'יומן'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _SupportAgentsListTab(),
                _ShiftsTab(),
                _KpiDashboardTab(),
                _EscalationConfigTab(),
                _RoutingOnlyTab(),
                _CannedResponsesTab(),
                _SelfServiceTab(),
                _ProactiveOnlyTab(),
                _SupportAuditLogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — Active support agents + add new
// ═══════════════════════════════════════════════════════════════════════════

class _SupportAgentsListTab extends StatefulWidget {
  const _SupportAgentsListTab();

  @override
  State<_SupportAgentsListTab> createState() =>
      _SupportAgentsListTabState();
}

class _SupportAgentsListTabState extends State<_SupportAgentsListTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _filterStatus = 'all'; // all | online | offline
  String _filterTier = 'all'; // all | agent | senior_agent | team_lead

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'support_agent')
        .limit(100)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'הוסף סוכן תמיכה',
          style: TextStyle(color: Colors.white),
        ),
        onPressed: () => _showAddAgentDialog(context),
      ),
      body: Column(
        children: [
          // ── Search bar + filter chips ─────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'חפש שם או מייל…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _filterChip('הכל', 'all', _filterStatus,
                            (v) => setState(() => _filterStatus = v)),
                        _filterChip('🟢 online', 'online', _filterStatus,
                            (v) => setState(() => _filterStatus = v)),
                        _filterChip('⚪ offline', 'offline', _filterStatus,
                            (v) => setState(() => _filterStatus = v)),
                        const SizedBox(width: 12),
                        _filterChip('כל הדרגות', 'all', _filterTier,
                            (v) => setState(() => _filterTier = v)),
                        _filterChip('סוכן', 'agent', _filterTier,
                            (v) => setState(() => _filterTier = v)),
                        _filterChip('בכיר', 'senior_agent', _filterTier,
                            (v) => setState(() => _filterTier = v)),
                        _filterChip('ראש צוות', 'team_lead', _filterTier,
                            (v) => setState(() => _filterTier = v)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'שגיאת טעינה: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                final allDocs = snap.data?.docs ?? [];

                // Client-side filter
                final docs = allDocs.where((d) {
                  final data = d.data();
                  final name = (data['name'] as String? ?? '').toLowerCase();
                  final email =
                      (data['email'] as String? ?? '').toLowerCase();
                  final ap = (data['agentProfile'] is Map)
                      ? (data['agentProfile'] as Map)
                      : const {};
                  final isOnline = ap['isOnline'] == true;
                  final tier = (ap['tier'] as String?) ?? 'agent';
                  if (_query.isNotEmpty &&
                      !name.contains(_query) &&
                      !email.contains(_query)) {
                    return false;
                  }
                  if (_filterStatus == 'online' && !isOnline) return false;
                  if (_filterStatus == 'offline' && isOnline) return false;
                  if (_filterTier != 'all' && tier != _filterTier) {
                    return false;
                  }
                  return true;
                }).toList();

                if (allDocs.isEmpty) {
                  return _emptyState(
                    'אין סוכני תמיכה עדיין',
                    'לחץ על הכפתור למטה כדי להפוך משתמש לסוכן',
                  );
                }
                if (docs.isEmpty) {
                  return _emptyState(
                    'אף סוכן לא תואם לפילטרים',
                    'נסה לאפס את החיפוש או הפילטרים',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final doc = docs[i];
                    final d = doc.data();
                    return _AgentCard(uid: doc.id, data: d);
                  },
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

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent_rounded,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, color: Color(0xFF6B7280))),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static void _showAddAgentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _AddAgentDialog(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AgentCard — single agent row with revoke action
// ═══════════════════════════════════════════════════════════════════════════

class _AgentCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;

  const _AgentCard({required this.uid, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'סוכן';
    final email = data['email'] as String? ?? '';
    final phone = data['phone'] as String? ?? '';
    final img = data['profileImage'] as String? ?? '';
    final roleUpdatedAt = data['roleUpdatedAt'] as Timestamp?;
    final since = roleUpdatedAt != null
        ? DateFormat('dd/MM/yyyy', 'he').format(roleUpdatedAt.toDate())
        : '—';
    final ap = (data['agentProfile'] is Map)
        ? (data['agentProfile'] as Map)
        : const {};
    final isOnline = ap['isOnline'] == true;
    final tier = (ap['tier'] as String?) ?? 'agent';
    final specialties = (ap['specialties'] is List)
        ? List<String>.from(ap['specialties'] as List)
        : <String>[];
    final maxConcurrent =
        (ap['maxConcurrentTickets'] as num?)?.toInt() ?? 5;

    final tierMeta = switch (tier) {
      'team_lead' => (
        const Color(0xFFEF4444),
        'TEAM LEAD',
        Icons.workspace_premium_rounded,
      ),
      'senior_agent' => (
        const Color(0xFFF59E0B),
        'SENIOR',
        Icons.shield_rounded,
      ),
      _ => (
        const Color(0xFF6366F1),
        'AGENT',
        Icons.headset_mic_rounded,
      ),
    };
    final tierColor = tierMeta.$1;
    final tierLabel = tierMeta.$2;
    final tierIcon = tierMeta.$3;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tierColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar with online dot
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        tierColor.withValues(alpha: 0.12),
                    backgroundImage: safeImageProvider(img),
                    child: safeImageProvider(img) == null
                        ? Text(
                            name.isNotEmpty ? name[0] : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: tierColor,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF9CA3AF),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 2),
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
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(tierIcon, size: 10, color: tierColor),
                              const SizedBox(width: 4),
                              Text(
                                tierLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: tierColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'מאז: $since · max $maxConcurrent בו־זמנית',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: Colors.red, size: 20),
                tooltip: 'הסר הרשאת סוכן',
                onPressed: () => _confirmRevoke(context, uid, name),
              ),
            ],
          ),
          // Specialties
          if (specialties.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: specialties.take(6).map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          // Daily perf — open tickets + breached SLA from live query
          const SizedBox(height: 10),
          _DailyAgentStats(uid: uid),
        ],
      ),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    String uid,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: const Text('הסרת הרשאת סוכן'),
        content: Text(
          'האם להסיר את הרשאת סוכן התמיכה מ-$name?\n'
          'הוא לא יוכל יותר לגשת ל-Support Workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('הסר'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await SupportAgentService.setUserRole(
        targetUserId: uid,
        newRole: SupportAgentService.roleUser,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ הרשאת סוכן הוסרה מ-$name'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Phase 6 — live "today" stats for an agent row.
// Reads open + 24h-closed + breached counts from Firestore in parallel
// without joining at the database level (small per-row cost; shown as
// pills on the agent card).
class _DailyAgentStats extends StatelessWidget {
  final String uid;
  const _DailyAgentStats({required this.uid});

  Future<({int open, int closedToday, int breached})> _load() async {
    final db = FirebaseFirestore.instance;
    final since = DateTime.now().subtract(const Duration(hours: 24));
    int open = 0;
    int closedToday = 0;
    int breached = 0;
    try {
      final mine = await db
          .collection('support_tickets')
          .where('assignedTo', isEqualTo: uid)
          .limit(200)
          .get();
      for (final d in mine.docs) {
        final t = d.data();
        final status = t['status'] as String? ?? 'open';
        if (status == 'open' || status == 'in_progress') {
          open++;
          if (t['lastAgentMessageAt'] == null) {
            final ts = t['createdAt'] as Timestamp?;
            if (ts != null &&
                DateTime.now().difference(ts.toDate()).inMinutes >= 15) {
              breached++;
            }
          }
        }
      }
      final closed = await db
          .collection('support_tickets')
          .where('closedBy', isEqualTo: uid)
          .where('closedAt', isGreaterThan: Timestamp.fromDate(since))
          .limit(200)
          .get();
      closedToday = closed.docs.length;
    } catch (_) {}
    return (open: open, closedToday: closedToday, breached: breached);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({int open, int closedToday, int breached})>(
      future: _load(),
      builder: (context, snap) {
        final s = snap.data;
        return Row(
          children: [
            _statPill(
              icon: Icons.inbox_rounded,
              label: 'פתוחות',
              value: '${s?.open ?? 0}',
              color: const Color(0xFF6366F1),
            ),
            const SizedBox(width: 6),
            _statPill(
              icon: Icons.check_circle_rounded,
              label: 'נסגרו 24ש',
              value: '${s?.closedToday ?? 0}',
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 6),
            _statPill(
              icon: Icons.local_fire_department_rounded,
              label: 'פיגור SLA',
              value: '${s?.breached ?? 0}',
              color: (s?.breached ?? 0) > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF9CA3AF),
            ),
          ],
        );
      },
    );
  }

  Widget _statPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AddAgentDialog — search user by email/name and promote
// ═══════════════════════════════════════════════════════════════════════════

class _AddAgentDialog extends StatefulWidget {
  const _AddAgentDialog();

  @override
  State<_AddAgentDialog> createState() => _AddAgentDialogState();
}

class _AddAgentDialogState extends State<_AddAgentDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  bool _granting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.length < 2) return;
    setState(() {
      _searching = true;
      _searchResults = [];
    });

    try {
      // Search by email and name (client-side filter on a small page)
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .limit(100)
          .get();
      final results = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final name = (d['name'] as String? ?? '').toLowerCase();
        final email = (d['email'] as String? ?? '').toLowerCase();
        // Skip existing admins/agents
        final role = SupportAgentService.resolveRole(d);
        if (role == SupportAgentService.roleAdmin) continue;
        if (role == SupportAgentService.roleSupportAgent) continue;

        if (name.contains(query) || email.contains(query)) {
          results.add({...d, 'uid': doc.id});
          if (results.length >= 10) break;
        }
      }
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאת חיפוש: $e')),
        );
      }
    }
  }

  Future<void> _grant(Map<String, dynamic> user) async {
    // Phase 6 — open the agent profile sheet first (tier + specialties +
    // languages + max concurrent), then commit role + agentProfile in one
    // call.
    final config = await _showAgentConfigSheet(user);
    if (config == null) return; // cancelled

    setState(() => _granting = true);
    try {
      // 1) Grant the role
      await SupportAgentService.setUserRole(
        targetUserId: user['uid'] as String,
        newRole: SupportAgentService.roleSupportAgent,
      );
      // 2) Write agentProfile in the same user doc (admin-can-write per rules)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user['uid'] as String)
          .set({
        'agentProfile': {
          'tier': config['tier'],
          'specialties': config['specialties'],
          'languages': config['languages'],
          'maxConcurrentTickets': config['maxConcurrentTickets'],
          'isOnline': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${user['name'] ?? "המשתמש"} הוגדר כסוכן תמיכה (${config['tier']})',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _granting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Phase 6 — shows a bottom sheet with the agentProfile fields. Returns
  /// the chosen config map, or null if the admin cancels.
  Future<Map<String, dynamic>?> _showAgentConfigSheet(
      Map<String, dynamic> user) async {
    String tier = 'agent';
    final specialties = <String>{};
    final languages = <String>{'he'};
    int maxConcurrent = 5;

    const tierOptions = <String, ({String label, String desc, Color color})>{
      'agent': (
        label: 'סוכן',
        desc: 'מטפל בפניות רגילות. מקס 5 בו־זמנית.',
        color: Color(0xFF6366F1),
      ),
      'senior_agent': (
        label: 'סוכן בכיר',
        desc: 'מקבל פניות VIP + הסלמות. מקס 8 בו־זמנית.',
        color: Color(0xFFF59E0B),
      ),
      'team_lead': (
        label: 'ראש צוות',
        desc: 'גם פניות + ניהול הצוות. מקס 10 בו־זמנית.',
        color: Color(0xFFEF4444),
      ),
    };

    const allSpecialties = <String, String>{
      'payments': '💳 תשלומים',
      'cleaning': '🧹 ניקיון',
      'technical': '🔧 טכני',
      'volunteer': '🤝 התנדבות',
      'account': '👤 חשבון',
      'home_services': '🔨 שירותי בית',
      'beauty': '💅 יופי',
      'pets': '🐕 חיות מחמד',
      'other': '📋 אחר',
    };

    const allLanguages = <String, String>{
      'he': '🇮🇱 עברית',
      'ar': '🇸🇦 ערבית',
      'en': '🇺🇸 אנגלית',
      'ru': '🇷🇺 רוסית',
      'es': '🇪🇸 ספרדית',
    };

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSB) => Column(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'הגדרות סוכן חדש',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            user['name'] as String? ??
                                user['email'] as String? ??
                                '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Tier ────────────────────────────────────────────
                    const Text(
                      'דרגה',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...tierOptions.entries.map((e) {
                      final selected = tier == e.key;
                      return InkWell(
                        onTap: () {
                          setSB(() {
                            tier = e.key;
                            maxConcurrent = e.key == 'team_lead'
                                ? 10
                                : e.key == 'senior_agent'
                                    ? 8
                                    : 5;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? e.value.color.withValues(alpha: 0.10)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? e.value.color
                                  : const Color(0xFFE5E7EB),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 18,
                                color: selected
                                    ? e.value.color
                                    : Colors.grey[400],
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.value.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: e.value.color,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      e.value.desc,
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
                    }),
                    const SizedBox(height: 16),
                    // ── Specialties ─────────────────────────────────────
                    const Text(
                      'התמחויות (בחר אחד או יותר)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ה־router יעדיף סוכן שהקטגוריה של הפנייה ב־specialties',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: allSpecialties.entries.map((e) {
                        final selected = specialties.contains(e.key);
                        return FilterChip(
                          label: Text(e.value,
                              style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          onSelected: (v) => setSB(() {
                            if (v) {
                              specialties.add(e.key);
                            } else {
                              specialties.remove(e.key);
                            }
                          }),
                          selectedColor:
                              const Color(0xFF6366F1).withValues(alpha: 0.15),
                          checkmarkColor: const Color(0xFF6366F1),
                          labelStyle: TextStyle(
                            color: selected
                                ? const Color(0xFF6366F1)
                                : Colors.grey[700],
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // ── Languages ───────────────────────────────────────
                    const Text(
                      'שפות',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: allLanguages.entries.map((e) {
                        final selected = languages.contains(e.key);
                        return FilterChip(
                          label: Text(e.value,
                              style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          onSelected: (v) => setSB(() {
                            if (v) {
                              languages.add(e.key);
                            } else if (languages.length > 1) {
                              languages.remove(e.key);
                            }
                          }),
                          selectedColor:
                              const Color(0xFF10B981).withValues(alpha: 0.15),
                          checkmarkColor: const Color(0xFF10B981),
                          labelStyle: TextStyle(
                            color: selected
                                ? const Color(0xFF10B981)
                                : Colors.grey[700],
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // ── Permissions table ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'הרשאות לפי דרגה',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _permRow('צפייה ופנייה לכל הפניות', true, true, true),
                          _permRow('סגירת פניות + CSAT', true, true, true),
                          _permRow('אימות זהות + flag', true, true, true),
                          _permRow('קבלת פניות VIP', false, true, true),
                          _permRow('קבלת הסלמות שלב 2', false, true, true),
                          _permRow('ניהול משמרות הצוות', false, false, true),
                          _permRow('Vault פיננסי / משיכות', false, false, false,
                              danger: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('ביטול'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, {
                            'tier': tier,
                            'specialties': specialties.toList(),
                            'languages': languages.toList(),
                            'maxConcurrentTickets': maxConcurrent,
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('שמור והוסף סוכן'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permRow(String label, bool agent, bool senior, bool lead,
      {bool danger = false}) {
    Widget cell(bool ok) {
      return Expanded(
        child: Center(
          child: Icon(
            ok
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            size: 14,
            color: ok
                ? const Color(0xFF10B981)
                : (danger
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFD1D5DB)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
            ),
          ),
          cell(agent),
          cell(senior),
          cell(lead),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: Color(0xFF6366F1), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'הוסף סוכן תמיכה',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'חפש משתמש לפי שם או מייל. אתה לא יכול להפוך משתמש שכבר אדמין או סוכן.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              // Search bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'שם או מייל...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searching ? null : _search,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('חפש'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Results
              if (_searchResults.isEmpty && !_searching && _searchCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'לא נמצאו תוצאות',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              if (_searchResults.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = _searchResults[i];
                      final name = u['name'] as String? ?? 'משתמש';
                      final email = u['email'] as String? ?? '';
                      final img = u['profileImage'] as String? ?? '';
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF6366F1)
                              .withValues(alpha: 0.12),
                          backgroundImage: safeImageProvider(img),
                          child: safeImageProvider(img) == null
                              ? Text(
                                  name.isNotEmpty ? name[0] : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6366F1),
                                  ),
                                )
                              : null,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          email,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          onPressed: _granting ? null : () => _grant(u),
                          child: const Text(
                            'הפוך לסוכן',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — Audit log of every action taken by support agents
// ═══════════════════════════════════════════════════════════════════════════

class _SupportAuditLogTab extends StatelessWidget {
  const _SupportAuditLogTab();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('support_audit_log')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'שגיאת טעינה: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_rounded,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'אין עדיין פעולות בלוג',
                  style:
                      TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _AuditLogRow(data: docs[i].data()),
        );
      },
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AuditLogRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final agentName = data['agentName'] as String? ??
        data['adminName'] as String? ??
        'צוות';
    final action = data['action'] as String? ?? '';
    final targetName = data['targetName'] as String? ?? '—';
    final reason = data['reason'] as String? ?? '';
    final ts = (data['createdAt'] as Timestamp?)?.toDate();

    final actionMeta = _actionMeta(action);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: actionMeta.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(actionMeta.icon, color: actionMeta.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        actionMeta.label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: actionMeta.color,
                        ),
                      ),
                    ),
                    if (ts != null)
                      Text(
                        DateFormat('dd/MM HH:mm', 'he').format(ts),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$agentName → $targetName',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _ActionMeta _actionMeta(String action) {
    return switch (action) {
      'verify_identity' => _ActionMeta(
          'אימות זהות',
          Icons.verified_user_rounded,
          const Color(0xFF10B981),
        ),
      'send_password_reset' => _ActionMeta(
          'איפוס סיסמה',
          Icons.lock_reset_rounded,
          const Color(0xFF6366F1),
        ),
      'flag_account' => _ActionMeta(
          'דגל חשבון',
          Icons.flag_rounded,
          const Color(0xFFEF4444),
        ),
      'unflag_account' => _ActionMeta(
          'הסר דגל',
          Icons.flag_outlined,
          const Color(0xFF6B7280),
        ),
      'set_role' => _ActionMeta(
          'שינוי תפקיד: ${data['beforeRole']} → ${data['afterRole']}',
          Icons.admin_panel_settings_rounded,
          const Color(0xFFF59E0B),
        ),
      _ => _ActionMeta(
          action,
          Icons.info_outline_rounded,
          const Color(0xFF6B7280),
        ),
    };
  }
}

class _ActionMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _ActionMeta(this.label, this.icon, this.color);
}

/// Phase 1 multi-role migration trigger — backfills the new
/// `roles[]` + `activeRole` fields on every user doc from the legacy
/// single-role flags. Idempotent: already-migrated users are skipped.
class _RoleMigrationBanner extends StatefulWidget {
  const _RoleMigrationBanner();

  @override
  State<_RoleMigrationBanner> createState() => _RoleMigrationBannerState();
}

class _RoleMigrationBannerState extends State<_RoleMigrationBanner> {
  bool _busy = false;

  Future<void> _run({required bool dryRun}) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final res = await SupportAgentService.migrateUserRoles(dryRun: dryRun);
      if (!mounted) return;
      final label = dryRun ? 'בדיקה יבשה' : 'מיגרציה';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$label הסתיימה — נסרקו ${res['scanned']}, '
            'עודכנו ${res['migrated']}, דולגו ${res['skipped']}, '
            'שגיאות ${res['errors']}',
          ),
          backgroundColor: (res['errors'] as int? ?? 0) > 0
              ? const Color(0xFFEF4444)
              : const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('שגיאה: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFF7ED),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.build_circle_rounded,
              color: Color(0xFFF59E0B), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'מיגרציית תפקידים (Phase 1): ממלא roles[] ו-activeRole '
              'על כל המשתמשים. בטוח להריץ שוב.',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : () => _run(dryRun: true),
            child: const Text('בדיקה יבשה'),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : () => _run(dryRun: false),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('הרץ מיגרציה'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 6 — Config tabs (Routing / Proactive / Escalation) + Self-Service
//
// Each tab reads from a single Firestore doc (`platform_settings/...`) and
// renders a focused list of toggles + steppers. Shared primitives live in
// `_ConfigField` to avoid copy-pasting layout code 4 times.
// ═══════════════════════════════════════════════════════════════════════════

class _ConfigField {
  /// Toggle row bound to one boolean field on the given doc.
  static Widget toggle({
    required String docPath,
    required String field,
    required bool current,
    required String title,
    required String subtitle,
  }) {
    return _ConfigToggleRow(
      docPath: docPath,
      field: field,
      current: current,
      title: title,
      subtitle: subtitle,
    );
  }

  /// Number stepper bound to one int field on the given doc.
  static Widget number({
    required String docPath,
    required String field,
    required int current,
    required String title,
    required int min,
    required int max,
  }) {
    return _ConfigNumberRow(
      docPath: docPath,
      field: field,
      current: current,
      title: title,
      min: min,
      max: max,
    );
  }

  /// Section header row.
  static Widget section(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              )),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF6B7280),
              )),
        ],
      ),
    );
  }

  /// Help banner shown at the bottom of config tabs.
  static Widget infoBanner(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigToggleRow extends StatelessWidget {
  final String docPath;
  final String field;
  final bool current;
  final String title;
  final String subtitle;

  const _ConfigToggleRow({
    required this.docPath,
    required this.field,
    required this.current,
    required this.title,
    required this.subtitle,
  });

  Future<void> _save(BuildContext context, bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .doc(docPath)
          .set({field: v}, SetOptions(merge: true));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('שמירה נכשלה: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    )),
              ],
            ),
          ),
          Switch.adaptive(
            value: current,
            activeColor: const Color(0xFF10B981),
            onChanged: (v) => _save(context, v),
          ),
        ],
      ),
    );
  }
}

class _ConfigNumberRow extends StatelessWidget {
  final String docPath;
  final String field;
  final int current;
  final String title;
  final int min;
  final int max;

  const _ConfigNumberRow({
    required this.docPath,
    required this.field,
    required this.current,
    required this.title,
    required this.min,
    required this.max,
  });

  Future<void> _save(BuildContext context, int v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .doc(docPath)
          .set({field: v}, SetOptions(merge: true));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('שמירה נכשלה: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                )),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            onPressed:
                current > min ? () => _save(context, current - 1) : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            alignment: Alignment.center,
            child: Text('$current',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                )),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            onPressed:
                current < max ? () => _save(context, current + 1) : null,
          ),
        ],
      ),
    );
  }
}

// ── Routing tab ────────────────────────────────────────────────────────────
class _RoutingOnlyTab extends StatelessWidget {
  const _RoutingOnlyTab();
  static const _doc = 'platform_settings/routing_config';
  static const _defaults = <String, dynamic>{
    'enableCategoryMatch': true,
    'enableLanguageMatch': true,
    'enableLoadBalancing': true,
    'enableVipRouting': true,
    'vipTrustThreshold': 90,
    'defaultMaxConcurrent': 5,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc(_doc).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = <String, dynamic>{
          ..._defaults,
          ...(snap.data?.data() ?? const {}),
        };
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConfigField.section('ניתוב חכם של פניות',
                'הכלל בוחר את הסוכן הטוב ביותר לפי score משוקלל'),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableCategoryMatch',
              current: d['enableCategoryMatch'] == true,
              title: '🏷️ התאמת קטגוריה',
              subtitle:
                  'מעדיף סוכנים שהקטגוריה של הפנייה ב־specialties שלהם',
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableLanguageMatch',
              current: d['enableLanguageMatch'] == true,
              title: '🌐 התאמת שפה',
              subtitle: 'מעדיף סוכנים שהשפה של הלקוח ב־languages',
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableLoadBalancing',
              current: d['enableLoadBalancing'] == true,
              title: '⚖️ איזון עומסים',
              subtitle: 'הסוכן עם מספר הפניות הפתוחות הנמוך ביותר',
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableVipRouting',
              current: d['enableVipRouting'] == true,
              title: '👑 ניתוב VIP',
              subtitle:
                  'לקוחות עם trustScore ≥ סף VIP מנותבים לסוכן בכיר/ראש צוות',
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'vipTrustThreshold',
              current: (d['vipTrustThreshold'] as num?)?.toInt() ?? 90,
              title: 'סף VIP (trustScore)',
              min: 0,
              max: 100,
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'defaultMaxConcurrent',
              current: (d['defaultMaxConcurrent'] as num?)?.toInt() ?? 5,
              title: 'ברירת־מחדל: מקסימום פניות פתוחות לסוכן',
              min: 1,
              max: 50,
            ),
            _ConfigField.infoBanner(
              'שינויים נכנסים לתוקף מיד. ה־CF onTicketCreatedAutoRoute רץ בכל יצירת פנייה חדשה.',
            ),
          ],
        );
      },
    );
  }
}

// ── Proactive tab ──────────────────────────────────────────────────────────
class _ProactiveOnlyTab extends StatelessWidget {
  const _ProactiveOnlyTab();
  static const _doc = 'platform_settings/routing_config';
  static const _defaults = <String, dynamic>{
    'enableProviderNoConfirm': true,
    'providerNoConfirmMinutes': 30,
    'enableProviderLate': true,
    'providerLateMinutes': 15,
    'enableProviderCancelled': true,
    'enablePaymentFailed': true,
    'paymentFailedMinutes': 60,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc(_doc).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = <String, dynamic>{
          ..._defaults,
          ...(snap.data?.data() ?? const {}),
        };

        // Live performance count: proactive tickets created today
        final today = DateTime.now();
        final start = DateTime(today.year, today.month, today.day);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConfigField.section('פניות Proactive',
                'מערכת פותחת פניות אוטומטית לפני שהלקוח מתלונן'),
            // Live performance card — count of proactive tickets today
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('support_tickets')
                  .where('type', isEqualTo: 'proactive')
                  .where('createdAt',
                      isGreaterThan: Timestamp.fromDate(start))
                  .snapshots(),
              builder: (ctx, tsnap) {
                final count = tsnap.data?.docs.length ?? 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚡ $count פניות נפתחו אוטומטית היום',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'בלי הטריגרים האלה הלקוחות היו צריכים להתלונן בעצמם',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableProviderNoConfirm',
              current: d['enableProviderNoConfirm'] == true,
              title: '⏰ נותן השירות לא אישר',
              subtitle: 'פתיחה אוטומטית X דקות אחרי paid_escrow ללא אישור',
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'providerNoConfirmMinutes',
              current:
                  (d['providerNoConfirmMinutes'] as num?)?.toInt() ?? 30,
              title: 'חלון זמן לאי־אישור (דקות)',
              min: 5,
              max: 240,
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableProviderLate',
              current: d['enableProviderLate'] == true,
              title: '🚗 נותן שירות מאחר',
              subtitle:
                  'הודעה אוטומטית כשהספק > X דקות אחרי המועד המתוכנן',
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'providerLateMinutes',
              current: (d['providerLateMinutes'] as num?)?.toInt() ?? 15,
              title: 'סף איחור (דקות)',
              min: 5,
              max: 120,
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableProviderCancelled',
              current: d['enableProviderCancelled'] == true,
              title: '❌ נותן שירות ביטל',
              subtitle: 'פנייה מיידית כשהספק מבטל הזמנה מאושרת',
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enablePaymentFailed',
              current: d['enablePaymentFailed'] == true,
              title: '💳 תשלום נכשל',
              subtitle: 'פנייה כשסטטוס ההזמנה הופך ל־payment_failed',
            ),
            _ConfigField.infoBanner(
              'ה־scheduler proactiveSlaMonitor רץ כל 5 דקות. כל טריגר בודק idempotency לפני יצירה.',
            ),
          ],
        );
      },
    );
  }
}

// ── Escalation tab ─────────────────────────────────────────────────────────
class _EscalationConfigTab extends StatelessWidget {
  const _EscalationConfigTab();
  static const _doc = 'platform_settings/escalation_config';
  static const _defaults = <String, dynamic>{
    'enableStage1': true,
    'stage1Minutes': 3,
    'enableStage2': true,
    'stage2Minutes': 7,
    'enableStage3': true,
    'stage3Minutes': 15,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc(_doc).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = <String, dynamic>{
          ..._defaults,
          ...(snap.data?.data() ?? const {}),
        };
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConfigField.section('הסלמת SLA',
                '3 שלבים — סוכן / סוכן בכיר / מנהל. כל שלב מתחיל ספירה מ־createdAt'),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableStage1',
              current: d['enableStage1'] == true,
              title: '⏰ שלב 1 — תזכורת לסוכן',
              subtitle: 'push לסוכן המוקצה + עדכון priority=high',
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'stage1Minutes',
              current: (d['stage1Minutes'] as num?)?.toInt() ?? 3,
              title: 'זמן שלב 1 (דקות)',
              min: 1,
              max: 30,
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableStage2',
              current: d['enableStage2'] == true,
              title: '🔥 שלב 2 — מעבר לסוכן בכיר',
              subtitle: 'הקצאה אוטומטית ל־senior_agent/team_lead',
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'stage2Minutes',
              current: (d['stage2Minutes'] as num?)?.toInt() ?? 7,
              title: 'זמן שלב 2 (דקות)',
              min: 2,
              max: 60,
            ),
            _ConfigField.toggle(
              docPath: _doc,
              field: 'enableStage3',
              current: d['enableStage3'] == true,
              title: '🚨 שלב 3 — התראה למנהל',
              subtitle: 'notifications לכל האדמינים + slaFailed=true',
            ),
            _ConfigField.number(
              docPath: _doc,
              field: 'stage3Minutes',
              current: (d['stage3Minutes'] as num?)?.toInt() ?? 15,
              title: 'זמן שלב 3 (דקות)',
              min: 5,
              max: 120,
            ),
            _ConfigField.infoBanner(
              'ה־CF checkSLA רץ כל דקה. כל שלב משתמש ב־slaStage כדי לא להפעיל את עצמו פעמיים.',
            ),
          ],
        );
      },
    );
  }
}

// ── Self-Service tab (bot performance) ─────────────────────────────────────
class _SelfServiceTab extends StatelessWidget {
  const _SelfServiceTab();

  String get _todayKey {
    final t = DateTime.now().toUtc();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc('bot_analytics/$_todayKey')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final sessions = (data['sessions'] as num?)?.toInt() ?? 0;
        final auto = (data['autoResolved'] as num?)?.toInt() ?? 0;
        final handoffs = (data['handoffs'] as num?)?.toInt() ?? 0;
        final rate =
            sessions > 0 ? '${((auto / sessions) * 100).round()}%' : '—';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConfigField.section('ביצועי בוט התמיכה',
                'מודל: gemini-2.5-flash-lite · נתוני $_todayKey'),
            // Big stats grid
            Row(
              children: [
                _bigStat('$sessions', 'שיחות',
                    Icons.chat_bubble_outline_rounded,
                    const Color(0xFF6366F1)),
                const SizedBox(width: 8),
                _bigStat('$auto', 'נפתרו ע"י הבוט',
                    Icons.check_circle_outline_rounded,
                    const Color(0xFF10B981)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _bigStat('$handoffs', 'הועברו לסוכן',
                    Icons.swap_horiz_rounded,
                    const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                _bigStat(rate, 'אחוז פתרון',
                    Icons.trending_up_rounded,
                    const Color(0xFF8B5CF6)),
              ],
            ),
            const SizedBox(height: 24),
            _ConfigField.section('תרחישים שהבוט מטפל בהם',
                'כל אינטנט שהמודל מזהה. שינוי דורש עדכון system prompt'),
            _scenarioRow('order_status', '📦 איפה ההזמנה?', true),
            _scenarioRow('password', '🔑 איפוס סיסמה', true),
            _scenarioRow('cancel', '❌ ביטול הזמנה', true),
            _scenarioRow('provider_no_show', '🚫 נותן השירות לא הגיע', false),
            _scenarioRow('payment', '💳 בעיה בתשלום', false),
            _scenarioRow('other', '🤷 שאר נושאים', false),
            _ConfigField.infoBanner(
              'תרחישים מסומנים בכתום מועברים אוטומטית לסוכן (לא ניתנים לפתרון אוטומטי).',
            ),
          ],
        );
      },
    );
  }

  Widget _bigStat(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scenarioRow(String intent, String label, bool autoResolves) {
    final color = autoResolves
        ? const Color(0xFF10B981)
        : const Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    )),
                const SizedBox(height: 2),
                Text(
                  'intent: $intent',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              autoResolves ? 'אוטומטי' : 'מועבר לסוכן',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 4 — KPI Dashboard tab
//
// Reads yesterday's agent_kpi/{date}_{uid} docs written by aggregateKPI CF.
// Shows team rollup at the top + per-agent table. The CF runs at 00:05 IST
// so "yesterday" is the most recent complete day.
// ═══════════════════════════════════════════════════════════════════════════
class _KpiDashboardTab extends StatelessWidget {
  const _KpiDashboardTab();

  String get _yesterdayKey {
    final y = DateTime.now().toUtc().subtract(const Duration(days: 1));
    return '${y.year.toString().padLeft(4, '0')}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = _yesterdayKey;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('agent_kpi')
          .where('date', isEqualTo: dateKey)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs.map((d) => d.data()).toList();
        final team = docs.firstWhere(
          (d) => d['team'] == true,
          orElse: () => const <String, dynamic>{},
        );
        final perAgent = docs.where((d) => d['team'] != true).toList()
          ..sort((a, b) => ((b['ticketsClosed'] as num?) ?? 0)
              .compareTo((a['ticketsClosed'] as num?) ?? 0));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'KPI · $dateKey',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'מתעדכן אוטומטית ב־00:05. אם אין נתונים ל־"אתמול" — ה־CF עדיין לא רץ או שלא היו פניות שנסגרו.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            if (team.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Center(
                  child: Text(
                    'אין נתוני KPI זמינים ל־אתמול',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
              )
            else
              _kpiTeamCard(team),
            const SizedBox(height: 20),
            if (perAgent.isNotEmpty) ...[
              const Text(
                'פירוט לפי סוכן',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              ...perAgent.map(_kpiAgentRow),
            ],
          ],
        );
      },
    );
  }

  Widget _kpiTeamCard(Map<String, dynamic> team) {
    final closed = (team['ticketsClosed'] as num?)?.toInt() ?? 0;
    final csat = (team['csatAvg'] as num?)?.toDouble();
    final fcr = (team['firstContactResolution'] as num?)?.toDouble();
    final avgResp = (team['avgResponseSeconds'] as num?)?.toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ביצועי הצוות',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _kpiPillWhite('$closed', 'נסגרו'),
              const SizedBox(width: 8),
              _kpiPillWhite(
                  csat == null ? '—' : csat.toStringAsFixed(1), 'CSAT'),
              const SizedBox(width: 8),
              _kpiPillWhite(
                  fcr == null ? '—' : '${(fcr * 100).round()}%', 'FCR'),
              const SizedBox(width: 8),
              _kpiPillWhite(
                  avgResp == null
                      ? '—'
                      : '${(avgResp / 60).toStringAsFixed(1)}דק\'',
                  'ממוצע תגובה'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiPillWhite(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiAgentRow(Map<String, dynamic> a) {
    final uid = a['agentUid'] as String? ?? '';
    final closed = (a['ticketsClosed'] as num?)?.toInt() ?? 0;
    final csat = (a['csatAvg'] as num?)?.toDouble();
    final fcr = (a['firstContactResolution'] as num?)?.toDouble();
    final avgResp = (a['avgResponseSeconds'] as num?)?.toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              uid,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6366F1),
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _kpiMiniPill('$closed', 'סגורות', const Color(0xFF10B981)),
          const SizedBox(width: 4),
          _kpiMiniPill(
            csat == null ? '—' : csat.toStringAsFixed(1),
            'CSAT',
            const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 4),
          _kpiMiniPill(
            fcr == null ? '—' : '${(fcr * 100).round()}%',
            'FCR',
            const Color(0xFF6366F1),
          ),
          const SizedBox(width: 4),
          _kpiMiniPill(
            avgResp == null ? '—' : '${(avgResp / 60).toStringAsFixed(0)}ד',
            'תגובה',
            const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  Widget _kpiMiniPill(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 4 — Shifts tab (basic weekly grid)
//
// Firestore: shifts/{YYYY-Www}/slots/{slotId}
//   agentUid, agentName, day (sunday..saturday), period (morning|afternoon|evening),
//   startTime, endTime, status
//
// This first version lets the admin add slots and view the grid. Drag & drop
// + gap detection ship in the next polish pass.
// ═══════════════════════════════════════════════════════════════════════════
class _ShiftsTab extends StatefulWidget {
  const _ShiftsTab();

  @override
  State<_ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<_ShiftsTab> {
  static const _days = <String>[
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];
  static const _dayLabels = <String>['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];
  static const _periods = <String>['morning', 'afternoon', 'evening'];
  static const _periodLabels = <String, String>{
    'morning': 'בוקר',
    'afternoon': 'צהריים',
    'evening': 'ערב',
  };

  String _weekIdOf(DateTime d) {
    // ISO-ish week id: YYYY-Www (start of week = Sunday to match Israel week)
    final offsetToSunday = d.weekday == 7 ? 0 : d.weekday;
    final sunday = d.subtract(Duration(days: offsetToSunday));
    final jan1 = DateTime(sunday.year, 1, 1);
    final days = sunday.difference(jan1).inDays;
    final week = ((days + jan1.weekday) / 7).ceil();
    return '${sunday.year}-W${week.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final weekId = _weekIdOf(DateTime.now());
    final slotsStream = FirebaseFirestore.instance
        .collection('shifts')
        .doc(weekId)
        .collection('slots')
        .snapshots();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFF9FAFB),
          child: Row(
            children: [
              Text(
                'שבוע $weekId',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showAddSlotDialog(weekId),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('הוסף משמרת'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: slotsStream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final slots = snap.data!.docs
                  .map((d) => {...d.data(), 'id': d.id})
                  .toList();
              return _buildGrid(slots, weekId);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> slots, String weekId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const SizedBox(width: 80),
              for (var i = 0; i < _days.length; i++)
                Container(
                  width: 90,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _dayLabels[i],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
            ],
          ),
          // Period rows
          for (final period in _periods)
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    _periodLabels[period]!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                for (final day in _days)
                  _cellFor(slots, day, period, weekId),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cellFor(
    List<Map<String, dynamic>> slots,
    String day,
    String period,
    String weekId,
  ) {
    final cell = slots.where(
      (s) => s['day'] == day && s['period'] == period,
    );
    final hasSlot = cell.isNotEmpty;
    final slot = hasSlot ? cell.first : null;
    return Container(
      width: 90,
      height: 62,
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: hasSlot
            ? const Color(0xFF10B981).withValues(alpha: 0.10)
            : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasSlot
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
      ),
      child: hasSlot
          ? _slotChip(slot!, weekId)
          : const Center(
              child: Text(
                'פנוי',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
    );
  }

  Widget _slotChip(Map<String, dynamic> slot, String weekId) {
    return InkWell(
      onTap: () => _confirmRemoveSlot(slot, weekId),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            slot['agentName'] as String? ?? slot['agentUid'] as String? ?? '',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF047857),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            '${slot['startTime'] ?? ''}—${slot['endTime'] ?? ''}',
            style: const TextStyle(fontSize: 9, color: Color(0xFF047857)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSlotDialog(String weekId) async {
    // Load support agents.
    final agentsSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'support_agent')
        .limit(50)
        .get();
    if (!mounted) return;
    final agents = agentsSnap.docs
        .map((d) => {
              'uid': d.id,
              'name': d.data()['name'] ?? d.data()['email'] ?? d.id,
            })
        .toList();
    if (agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין סוכני תמיכה זמינים')),
      );
      return;
    }

    String? selectedAgent = agents.first['uid'] as String;
    String selectedDay = _days.first;
    String selectedPeriod = _periods.first;
    String startTime = '08:00';
    String endTime = '14:00';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: const Text('הוסף משמרת'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedAgent,
                  decoration: const InputDecoration(labelText: 'סוכן'),
                  items: [
                    for (final a in agents)
                      DropdownMenuItem(
                        value: a['uid'] as String,
                        child: Text(a['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setSB(() => selectedAgent = v),
                ),
                DropdownButtonFormField<String>(
                  value: selectedDay,
                  decoration: const InputDecoration(labelText: 'יום'),
                  items: [
                    for (var i = 0; i < _days.length; i++)
                      DropdownMenuItem(
                        value: _days[i],
                        child: Text(_dayLabels[i]),
                      ),
                  ],
                  onChanged: (v) => setSB(() => selectedDay = v ?? selectedDay),
                ),
                DropdownButtonFormField<String>(
                  value: selectedPeriod,
                  decoration: const InputDecoration(labelText: 'חלק מהיום'),
                  items: [
                    for (final p in _periods)
                      DropdownMenuItem(
                          value: p, child: Text(_periodLabels[p]!)),
                  ],
                  onChanged: (v) =>
                      setSB(() => selectedPeriod = v ?? selectedPeriod),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: startTime,
                        decoration:
                            const InputDecoration(labelText: 'שעת התחלה'),
                        onChanged: (v) => startTime = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: endTime,
                        decoration: const InputDecoration(labelText: 'שעת סיום'),
                        onChanged: (v) => endTime = v,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedAgent == null) return;
                final name = agents.firstWhere(
                    (a) => a['uid'] == selectedAgent)['name'] as String;
                await FirebaseFirestore.instance
                    .collection('shifts')
                    .doc(weekId)
                    .collection('slots')
                    .add({
                  'agentUid': selectedAgent,
                  'agentName': name,
                  'day': selectedDay,
                  'period': selectedPeriod,
                  'startTime': startTime,
                  'endTime': endTime,
                  'status': 'scheduled',
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveSlot(
      Map<String, dynamic> slot, String weekId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הסר משמרת'),
        content: Text(
          'להסיר את המשמרת של ${slot['agentName'] ?? slot['agentUid']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444)),
            child: const Text('הסר'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = slot['id'] as String?;
    if (id == null) return;
    await FirebaseFirestore.instance
        .collection('shifts')
        .doc(weekId)
        .collection('slots')
        .doc(id)
        .delete();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 4 — Canned Responses admin tab
//
// CRUD over the `canned_responses` collection. Admin edits title, body,
// shortcut, category, isGlobal. Body supports {customerName}, {ticketId},
// {agentName} placeholders.
// ═══════════════════════════════════════════════════════════════════════════
class _CannedResponsesTab extends StatelessWidget {
  const _CannedResponsesTab();

  Future<void> _showEditor(
    BuildContext context, {
    String? templateId,
    Map<String, dynamic>? existing,
  }) async {
    final titleCtrl =
        TextEditingController(text: existing?['title'] as String? ?? '');
    final bodyCtrl =
        TextEditingController(text: existing?['body'] as String? ?? '');
    final shortcutCtrl = TextEditingController(
        text: existing?['shortcut'] as String? ?? '');
    final categoryCtrl = TextEditingController(
        text: existing?['category'] as String? ?? '');
    bool isGlobal = existing?['isGlobal'] != false; // default true

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: Text(templateId == null ? 'תבנית חדשה' : 'ערוך תבנית'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'כותרת',
                      hintText: 'לדוגמה: 👋 ברוך הבא',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: shortcutCtrl,
                    decoration: const InputDecoration(
                      labelText: 'קיצור (shortcut)',
                      hintText: '/hi  — נפתח בהקלדת "/" בקומפוזר',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: categoryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'קטגוריה',
                      hintText: 'greeting / refund / apology …',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'גוף התבנית',
                      hintText:
                          '{customerName} / {ticketId} / {agentName} נתמכים',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('גלובלי (כל הסוכנים)'),
                    subtitle: const Text('אם כבוי — מוצג רק ליוצר'),
                    value: isGlobal,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) => setSB(() => isGlobal = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (templateId != null)
              TextButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('canned_responses')
                      .doc(templateId)
                      .delete();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style:
                    TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                child: const Text('מחק'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final body = bodyCtrl.text.trim();
                if (title.isEmpty || body.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('כותרת וגוף חובה')),
                  );
                  return;
                }
                final payload = <String, dynamic>{
                  'title': title,
                  'body': body,
                  'shortcut': shortcutCtrl.text.trim(),
                  'category': categoryCtrl.text.trim(),
                  'isGlobal': isGlobal,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                final coll = FirebaseFirestore.instance
                    .collection('canned_responses');
                if (templateId == null) {
                  payload['createdAt'] = FieldValue.serverTimestamp();
                  payload['createdBy'] = 'admin';
                  await coll.add(payload);
                } else {
                  await coll.doc(templateId).update(payload);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add_rounded),
        label: const Text('תבנית חדשה'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('canned_responses')
            .orderBy('category')
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'אין תבניות עדיין — הוסף ראשונה בלחיצה על "+"',
                  style: TextStyle(color: Color(0xFF6B7280)),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final title = data['title'] as String? ?? '';
              final body = data['body'] as String? ?? '';
              final shortcut = data['shortcut'] as String? ??
                  (data['category'] != null ? '/${data['category']}' : '');
              final isGlobal = data['isGlobal'] != false;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            shortcut.isEmpty ? '—' : shortcut,
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
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        if (!isGlobal)
                          const Tooltip(
                            message: 'אישי בלבד',
                            child: Icon(Icons.person_outline,
                                size: 14, color: Color(0xFF9CA3AF)),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          onPressed: () => _showEditor(
                            context,
                            templateId: d.id,
                            existing: data,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
