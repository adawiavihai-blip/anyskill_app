import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../providers/admin_user_detail_provider.dart';
import '../providers/admin_users_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Admin User Detail Screen — full command center for a single user.
///
/// Uses `.family` providers (autoDispose) so each user's data is streamed
/// independently and GC'd when the admin navigates away.
// ─────────────────────────────────────────────────────────────────────────────

class AdminUserDetailScreen extends ConsumerStatefulWidget {
  const AdminUserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<AdminUserDetailScreen> createState() =>
      _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState
    extends ConsumerState<AdminUserDetailScreen> {
  static const _kIndigo = Color(0xFF6366F1);
  static const _kPurple = Color(0xFF8B5CF6);
  static const _kGreen = Color(0xFF10B981);
  static const _kRed = Color(0xFFEF4444);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kDark = Color(0xFF1A1A2E);
  static const _kMuted = Color(0xFF6B7280);

  final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  // ── Safe image provider (same logic as profile_screen) ─────────────────

  static ImageProvider? _safeImage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return NetworkImage(raw);
    try {
      final b64 = raw.contains(',') ? raw.split(',').last : raw;
      return MemoryImage(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userDetailProvider(widget.userId));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('שגיאה: $e')),
        data: (data) => _buildBody(data),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'משתמש';
    final email = data['email'] as String? ?? '';
    final phone =
        (data['phone'] as String? ?? data['phoneNumber'] as String? ?? '')
            .trim();
    final profileImg = data['profileImage'] as String? ?? '';
    final avatar = _safeImage(profileImg);
    final isProvider = data['isProvider'] == true;
    final isVerified = data['isVerified'] == true;
    final isBanned = data['isBanned'] == true;
    final isOnline = data['isOnline'] == true;
    final isAdmin = data['isAdmin'] == true;
    final isPro = data['isAnySkillPro'] == true;
    final rating = (data['rating'] as num? ?? 0).toDouble();
    final reviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    final balance = (data['balance'] as num? ?? 0).toDouble();
    final pendingBalance =
        (data['pendingBalance'] as num? ?? 0).toDouble();
    final xp = (data['xp'] as num? ?? 0).toInt();
    final serviceType = data['serviceType'] as String? ?? '';
    final subCategory = data['subCategory'] as String? ?? '';
    final aboutMe = data['aboutMe'] as String? ?? '';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final lastOnline = (data['lastOnlineAt'] as Timestamp?)?.toDate();
    final streak = (data['streak'] as num? ?? 0).toInt();
    final cancellationPolicy =
        data['cancellationPolicy'] as String? ?? 'flexible';
    final adminNote = data['adminNote'] as String? ?? '';

    return CustomScrollView(
      slivers: [
        // ── App bar with hero avatar ──────────────────────────────────
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: _kIndigo,
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kIndigo, _kPurple],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatar,
                          onBackgroundImageError:
                              avatar != null ? (_, __) {} : null,
                          child: avatar == null
                              ? const Icon(Icons.person,
                                  size: 40, color: Colors.white70)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: isOnline ? _kGreen : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              color: Colors.white, size: 18),
                        ],
                        if (isPro) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kAmber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('PRO',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ],
                    ),
                    Text(email,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) => _handleMenuAction(v, data),
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'verify',
                    child: ListTile(
                        leading: Icon(Icons.verified, color: Colors.blue),
                        title: Text('אימות / ביטול אימות'))),
                const PopupMenuItem(
                    value: 'ban',
                    child: ListTile(
                        leading:
                            Icon(Icons.block, color: Colors.orange),
                        title: Text('חסום / שחרר'))),
                const PopupMenuItem(
                    value: 'promote',
                    child: ListTile(
                        leading:
                            Icon(Icons.star_rounded, color: Colors.amber),
                        title: Text('קדם / בטל קידום'))),
                const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_forever,
                            color: Colors.red),
                        title: Text('מחק חשבון'))),
              ],
            ),
          ],
        ),

        // ── Status chips ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(isProvider ? 'ספק' : 'לקוח',
                    isProvider ? _kIndigo : _kGreen),
                if (isAdmin)
                  _chip('אדמין', _kPurple),
                if (isBanned)
                  _chip('חסום', _kRed),
                if (isOnline)
                  _chip('אונליין', _kGreen)
                else
                  _chip('אופליין', _kMuted),
                if (streak > 0)
                  _chip('סטריק $streak', _kAmber),
                _chip('XP: $xp', _kIndigo),
              ],
            ),
          ),
        ),

        // ── Quick stats ───────────────────────────────────────────────
        SliverToBoxAdapter(child: _buildQuickStats(data)),

        // ── Personal details ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: _section(
            'פרטים אישיים',
            Icons.person_outline_rounded,
            Column(
              children: [
                _detailRow('טלפון', phone.isEmpty ? '—' : phone),
                _detailRow('קטגוריה',
                    serviceType.isEmpty ? '—' : '$serviceType${subCategory.isNotEmpty ? ' › $subCategory' : ''}'),
                _detailRow('מדיניות ביטול', cancellationPolicy),
                _detailRow('יתרה', '₪${balance.toStringAsFixed(2)}'),
                _detailRow(
                    'יתרה ממתינה', '₪${pendingBalance.toStringAsFixed(2)}'),
                if (aboutMe.isNotEmpty) ...[
                  const Divider(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(aboutMe,
                        style: const TextStyle(
                            fontSize: 13, color: _kMuted, height: 1.5)),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── User timeline ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _section(
            'ציר זמן',
            Icons.timeline_rounded,
            Column(
              children: [
                _timelineItem(
                  Icons.person_add_rounded,
                  'הצטרפות',
                  createdAt != null ? _fmt.format(createdAt) : '—',
                  _kGreen,
                ),
                _timelineItem(
                  Icons.wifi_rounded,
                  'נראה לאחרונה',
                  lastOnline != null ? _fmt.format(lastOnline) : '—',
                  _kIndigo,
                ),
                _timelineItem(
                  Icons.star_rounded,
                  'דירוג',
                  reviewsCount > 0
                      ? '${rating.toStringAsFixed(1)} ($reviewsCount ביקורות)'
                      : 'אין ביקורות עדיין',
                  _kAmber,
                ),
              ],
            ),
          ),
        ),

        // ── Admin note ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _section(
            'הערת מנהל',
            Icons.edit_note_rounded,
            GestureDetector(
              onTap: () => _showEditNoteDialog(adminNote),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: adminNote.isEmpty
                      ? Colors.grey.shade50
                      : _kAmber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: adminNote.isEmpty
                          ? Colors.grey.shade200
                          : _kAmber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        adminNote.isEmpty ? 'לחץ להוספת הערה...' : adminNote,
                        style: TextStyle(
                          fontSize: 13,
                          color: adminNote.isEmpty ? _kMuted : _kDark,
                          fontStyle: adminNote.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                    Icon(Icons.edit_rounded,
                        size: 16,
                        color: adminNote.isEmpty ? _kMuted : _kAmber),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Action center ─────────────────────────────────────────────
        SliverToBoxAdapter(child: _buildActionCenter(data)),

        // ── Transaction history ───────────────────────────────────────
        SliverToBoxAdapter(child: _buildTransactions()),

        // ── Audit log ─────────────────────────────────────────────────
        SliverToBoxAdapter(child: _buildAuditLog()),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  // ── Quick stats cards ──────────────────────────────────────────────────

  Widget _buildQuickStats(Map<String, dynamic> data) {
    final rating = (data['rating'] as num? ?? 0).toDouble();

    final txAsync = ref.watch(userTransactionsProvider(widget.userId));
    final jobsAsync = ref.watch(userJobsProvider(widget.userId));

    final txCount = txAsync.valueOrNull?.length ?? 0;
    final jobCount = jobsAsync.valueOrNull?.length ?? 0;
    final lifetimeValue = txAsync.valueOrNull?.fold<double>(
            0, (acc, tx) => acc + ((tx['amount'] as num?) ?? 0).toDouble()) ??
        0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
              child: _statCard('עסקאות', '$txCount', Icons.receipt_long_rounded,
                  _kIndigo)),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard('עבודות', '$jobCount',
                  Icons.work_outline_rounded, _kPurple)),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard(
                  'דירוג',
                  rating > 0 ? rating.toStringAsFixed(1) : '—',
                  Icons.star_rounded,
                  _kAmber)),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard(
                  'LTV',
                  '₪${lifetimeValue.toStringAsFixed(0)}',
                  Icons.account_balance_wallet_rounded,
                  _kGreen)),
        ],
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: _kMuted)),
        ],
      ),
    );
  }

  // ── Action center ──────────────────────────────────────────────────────

  Widget _buildActionCenter(Map<String, dynamic> data) {
    final isVerified = data['isVerified'] == true;
    final isBanned = data['isBanned'] == true;
    final isPromoted = data['isPromoted'] == true;
    final name = data['name'] as String? ?? 'משתמש';

    return _section(
      'פעולות מנהל',
      Icons.admin_panel_settings_rounded,
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: isVerified
                      ? Icons.verified
                      : Icons.verified_outlined,
                  label: isVerified ? 'בטל אימות' : 'אמת',
                  color: Colors.blue,
                  active: isVerified,
                  onTap: () {
                    ref
                        .read(adminUsersNotifierProvider.notifier)
                        .toggleVerified(widget.userId, isVerified);
                    _logAuditAction(
                        isVerified ? 'ביטול אימות' : 'אימות',
                        name);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: isBanned ? Icons.lock_open : Icons.block,
                  label: isBanned ? 'שחרר' : 'חסום',
                  color: Colors.orange,
                  active: isBanned,
                  onTap: () {
                    ref
                        .read(adminUsersNotifierProvider.notifier)
                        .toggleBanned(widget.userId, isBanned);
                    _logAuditAction(
                        isBanned ? 'שחרור חסימה' : 'חסימה', name);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: isPromoted
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: isPromoted ? 'בטל קידום' : 'קדם',
                  color: _kAmber,
                  active: isPromoted,
                  onTap: () {
                    ref
                        .read(adminUsersNotifierProvider.notifier)
                        .togglePromoted(widget.userId, isPromoted);
                    _logAuditAction(
                        isPromoted ? 'ביטול קידום' : 'קידום', name);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.notifications_active_rounded,
                  label: 'שלח התראה',
                  color: _kIndigo,
                  onTap: () => _showSendNotificationDialog(data),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: Icons.add_card_rounded,
                  label: 'טען ארנק',
                  color: _kGreen,
                  onTap: () => _showTopUpDialog(data),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: Icons.visibility_rounded,
                  label: 'צפה כמשתמש',
                  color: _kPurple,
                  onTap: () => _showViewAsUser(data),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.12)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.4)
                  : Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  // ── Transactions section ───────────────────────────────────────────────

  Widget _buildTransactions() {
    final txAsync = ref.watch(userTransactionsProvider(widget.userId));

    return _section(
      'היסטוריית עסקאות',
      Icons.receipt_long_rounded,
      txAsync.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Text('שגיאה: $e'),
        data: (txs) {
          if (txs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('אין עסקאות עדיין',
                  style: TextStyle(color: _kMuted, fontSize: 13)),
            );
          }
          final display = txs.take(10).toList();
          return Column(
            children: [
              for (final tx in display)
                _transactionRow(tx),
              if (txs.length > 10)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '+${txs.length - 10} עסקאות נוספות',
                      style: const TextStyle(
                          color: _kIndigo,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _transactionRow(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num? ?? 0).toDouble();
    final type = tx['type'] as String? ?? '';
    final ts = (tx['timestamp'] as Timestamp?)?.toDate();
    final isSender = tx['senderId'] == widget.userId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isSender
                  ? _kRed.withValues(alpha: 0.1)
                  : _kGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isSender
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: isSender ? _kRed : _kGreen,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.isEmpty ? 'עסקה' : type,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (ts != null)
                  Text(_fmt.format(ts),
                      style: const TextStyle(
                          fontSize: 11, color: _kMuted)),
              ],
            ),
          ),
          Text(
            '${isSender ? "-" : "+"}₪${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSender ? _kRed : _kGreen,
            ),
          ),
        ],
      ),
    );
  }

  // ── Audit log section ──────────────────────────────────────────────────

  Widget _buildAuditLog() {
    final logAsync = ref.watch(userAuditLogProvider(widget.userId));

    return _section(
      'יומן פעולות מנהל',
      Icons.history_rounded,
      logAsync.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, __) => const Text('אין יומן פעולות',
            style: TextStyle(color: _kMuted, fontSize: 13)),
        data: (logs) {
          if (logs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('אין פעולות מנהל רשומות',
                  style: TextStyle(color: _kMuted, fontSize: 13)),
            );
          }
          return Column(
            children: [
              for (final log in logs.take(20))
                _auditRow(log),
            ],
          );
        },
      ),
    );
  }

  Widget _auditRow(Map<String, dynamic> log) {
    final action = log['action'] as String? ?? '';
    final adminName = log['adminName'] as String? ?? 'מנהל';
    final ts = (log['createdAt'] as Timestamp?)?.toDate();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kIndigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: _kIndigo, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  '$adminName${ts != null ? " · ${_fmt.format(ts)}" : ""}',
                  style: const TextStyle(fontSize: 11, color: _kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared layout helpers ──────────────────────────────────────────────

  Widget _section(String title, IconData icon, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                      color: _kIndigo,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: _kIndigo),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kDark)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: _kMuted)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kDark)),
        ],
      ),
    );
  }

  Widget _timelineItem(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: _kMuted)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kDark)),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────

  void _handleMenuAction(String action, Map<String, dynamic> data) {
    final notifier = ref.read(adminUsersNotifierProvider.notifier);
    final name = data['name'] as String? ?? 'משתמש';

    switch (action) {
      case 'verify':
        final current = data['isVerified'] == true;
        notifier.toggleVerified(widget.userId, current);
        _logAuditAction(current ? 'ביטול אימות' : 'אימות', name);
        break;
      case 'ban':
        final current = data['isBanned'] == true;
        notifier.toggleBanned(widget.userId, current);
        _logAuditAction(current ? 'שחרור חסימה' : 'חסימה', name);
        break;
      case 'promote':
        final current = data['isPromoted'] == true;
        notifier.togglePromoted(widget.userId, current);
        _logAuditAction(
            current ? 'ביטול קידום' : 'קידום', name);
        break;
      case 'delete':
        _confirmDelete(name);
        break;
    }
  }

  void _showEditNoteDialog(String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הערת מנהל'),
        content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'כתוב הערה...', border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(adminUsersNotifierProvider.notifier)
                  .setAdminNote(widget.userId, ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  void _showSendNotificationDialog(Map<String, dynamic> data) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final name = data['name'] as String? ?? 'משתמש';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('שלח התראה ל-$name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                  labelText: 'כותרת', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'תוכן ההודעה',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await FirebaseFirestore.instance
                  .collection('notifications')
                  .add({
                'userId': widget.userId,
                'title': titleCtrl.text.trim(),
                'body': bodyCtrl.text.trim(),
                'type': 'admin_message',
                'isRead': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
              _logAuditAction(
                  'שליחת התראה: ${titleCtrl.text.trim()}', name);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('התראה נשלחה ל-$name'),
                  backgroundColor: _kGreen,
                ));
              }
            },
            child: const Text('שלח'),
          ),
        ],
      ),
    );
  }

  void _showTopUpDialog(Map<String, dynamic> data) {
    final amountCtrl = TextEditingController();
    final name = data['name'] as String? ?? 'משתמש';
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('הטענת ארנק ל-$name'),
        content: TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                hintText: 'סכום', suffixText: '₪',
                border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(amountCtrl.text.trim());
              if (val == null || val <= 0) return;
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.runTransaction((tx) async {
                final userRef = FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.userId);
                tx.update(
                    userRef, {'balance': FieldValue.increment(val)});
                tx.set(
                    FirebaseFirestore.instance
                        .collection('transactions')
                        .doc(),
                    {
                      'userId': widget.userId,
                      'amount': val,
                      'title': 'טעינת ארנק ע״י מנהל',
                      'timestamp': FieldValue.serverTimestamp(),
                      'type': 'admin_topup',
                    });
              });
              _logAuditAction(
                  'טעינת ארנק: ₪${val.toStringAsFixed(0)}', name);
              messenger.showSnackBar(SnackBar(
                  content: Text('נטענו ₪$val ל-$name'),
                  backgroundColor: _kGreen));
            },
            child: const Text('אשר'),
          ),
        ],
      ),
    );
  }

  void _showViewAsUser(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'משתמש';
    final email = data['email'] as String? ?? '';
    final profileImg = data['profileImage'] as String? ?? '';
    final avatar = _safeImage(profileImg);
    final isProvider = data['isProvider'] == true;
    final balance = (data['balance'] as num? ?? 0).toDouble();
    final xp = (data['xp'] as num? ?? 0).toInt();
    final serviceType = data['serviceType'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_rounded,
                      size: 14, color: _kPurple),
                  SizedBox(width: 6),
                  Text('מצב צפייה כמשתמש',
                      style: TextStyle(
                          fontSize: 12,
                          color: _kPurple,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundImage: avatar,
                onBackgroundImageError:
                    avatar != null ? (_, __) {} : null,
                child: avatar == null
                    ? const Icon(Icons.person, size: 36)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Center(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold))),
            Center(
                child: Text(email,
                    style: const TextStyle(
                        fontSize: 13, color: _kMuted))),
            const SizedBox(height: 20),
            _detailRow('תפקיד', isProvider ? 'ספק שירות' : 'לקוח'),
            if (serviceType.isNotEmpty)
              _detailRow('קטגוריה', serviceType),
            _detailRow('יתרה', '₪${balance.toStringAsFixed(2)}'),
            _detailRow('XP', '$xp'),
            const Divider(height: 24),
            const Center(
              child: Text(
                'זהו מצב צפייה בלבד — לא ניתן לבצע פעולות.',
                style: TextStyle(fontSize: 12, color: _kMuted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String name) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקה סופית'),
        content: Text(
            'האם למחוק את $name לצמיתות?\nלא ניתן לשחזר.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFunctions.instance
                    .httpsCallable('deleteUser')
                    .call({'uid': widget.userId});
                _logAuditAction('מחיקת חשבון', name);
                if (mounted) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('$name נמחק'),
                      backgroundColor: _kGreen));
                  Navigator.pop(context);
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                    content: Text('שגיאה: $e'),
                    backgroundColor: _kRed));
              }
            },
            child:
                const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Audit log writer ───────────────────────────────────────────────────

  Future<void> _logAuditAction(String action, String targetName) async {
    final admin = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseFirestore.instance.collection('admin_audit_log').add({
        'targetUserId': widget.userId,
        'targetName': targetName,
        'action': action,
        'adminUid': admin?.uid ?? '',
        'adminName': admin?.displayName ?? admin?.email ?? 'מנהל',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
