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
    _tabController = TabController(length: 2, vsync: this);
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
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF6366F1),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF6366F1),
              indicatorWeight: 3,
              tabs: const [
                Tab(
                  icon: Icon(Icons.support_agent_rounded, size: 20),
                  text: 'סוכני תמיכה',
                ),
                Tab(
                  icon: Icon(Icons.history_rounded, size: 20),
                  text: 'יומן פעולות',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _SupportAgentsListTab(),
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

class _SupportAgentsListTab extends StatelessWidget {
  const _SupportAgentsListTab();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'support_agent')
        .limit(50)
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.support_agent_rounded,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'אין סוכני תמיכה עדיין',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'לחץ על הכפתור למטה כדי להפוך משתמש לסוכן',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
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
        ? DateFormat('dd/MM/yyyy').format(roleUpdatedAt.toDate())
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor:
                const Color(0xFF6366F1).withValues(alpha: 0.12),
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
                        color: const Color(0xFF6366F1)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'AGENT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
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
                  'מאז: $since',
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
    setState(() => _granting = true);
    try {
      await SupportAgentService.setUserRole(
        targetUserId: user['uid'] as String,
        newRole: SupportAgentService.roleSupportAgent,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${user['name'] ?? "המשתמש"} הוגדר כסוכן תמיכה',
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
                        DateFormat('dd/MM HH:mm').format(ts),
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
