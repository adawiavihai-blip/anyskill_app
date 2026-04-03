import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
      floatingActionButton: userAsync.whenOrNull(
        data: (data) => _buildSpeedDial(data),
      ),
    );
  }

  // ── Helper: pick first non-empty string from multiple field names ─────
  static String _pickString(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  // ── Helper: pick first valid Timestamp from multiple field names ─────
  static DateTime? _pickDate(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return null;
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final name = _pickString(data, ['name']).isEmpty
        ? 'משתמש'
        : data['name'] as String;
    final email = _pickString(data, ['email']);
    final phone = _pickString(data, ['phone', 'phoneNumber', 'mobile']);
    final profileImg = _pickString(data, ['profileImage', 'photoURL', 'imageUrl']);
    final avatar = _safeImage(profileImg);
    final isProvider = data['isProvider'] == true;
    final isVerified = data['isVerified'] == true;
    final isBanned = data['isBanned'] == true;
    final isOnline = data['isOnline'] == true;
    final isAdmin = data['isAdmin'] == true;
    final isPro = data['isAnySkillPro'] == true;
    final firestoreRating = (data['rating'] as num? ?? 0).toDouble();
    final firestoreReviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    // Live reviews for fallback rating calculation
    final liveReviews = ref.watch(userReviewsProvider(widget.userId)).valueOrNull ?? [];
    final rating = firestoreRating > 0 ? firestoreRating : _liveRating(liveReviews);
    final reviewsCount = firestoreReviewsCount > 0 ? firestoreReviewsCount : liveReviews.length;
    final balance = (data['balance'] as num? ?? 0).toDouble();
    final pendingBalance =
        (data['pendingBalance'] as num? ?? 0).toDouble();
    final xp = (data['xp'] as num? ?? 0).toInt();
    final serviceType = _pickString(data, ['serviceType']);
    final subCategory = _pickString(data, ['subCategory']);
    final aboutMe = _pickString(data, ['aboutMe']);
    final createdAt = _pickDate(data, ['createdAt', 'joinDate', 'registrationTimestamp']);
    final lastOnline = _pickDate(data, ['lastOnlineAt', 'lastActiveAt', 'lastActive', 'lastSeen', 'lastLogin']);
    final streak = (data['streak'] as num? ?? 0).toInt();
    final cancellationPolicy =
        _pickString(data, ['cancellationPolicy']).isEmpty
            ? 'flexible'
            : data['cancellationPolicy'] as String;
    final adminNote = _pickString(data, ['adminNote']);

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

        // ── Status chips (role-aware) ─────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(isProvider ? 'ספק שירות' : 'לקוח',
                    isProvider ? _kIndigo : _kGreen),
                if (isAdmin)
                  _chip('אדמין', _kPurple),
                if (isBanned)
                  _chip('חסום', _kRed),
                if (isOnline)
                  _chip('אונליין', _kGreen)
                else
                  _chip('אופליין', _kMuted),
                // Provider-only chips
                if (isProvider) ...[
                  if (streak > 0) _chip('סטריק $streak', _kAmber),
                  _chip('XP: $xp', _kIndigo),
                  if (isPro) _chip('AnySkill Pro', const Color(0xFFEC4899)),
                ],
              ],
            ),
          ),
        ),

        // ── Quick stats (role-aware) ──────────────────────────────────
        SliverToBoxAdapter(
          child: isProvider
              ? _buildProviderStats(data)
              : _buildCustomerStats(data),
        ),

        // ── Fix profile image (admin only, shown when image missing) ──
        if (profileImg.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => _fixProfileImage(data),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _kAmber.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.image_not_supported_rounded,
                          color: _kAmber, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'תמונת פרופיל חסרה — לחץ לסנכרון מ-Google Auth',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kAmber),
                        ),
                      ),
                      Icon(Icons.sync_rounded,
                          color: _kAmber, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Personal details (role-aware) ────────────────────────────
        SliverToBoxAdapter(
          child: _section(
            'פרטים אישיים',
            Icons.person_outline_rounded,
            Column(
              children: [
                _detailRow('טלפון', phone.isEmpty ? 'לא הוזן' : phone),
                _detailRow('אימייל', email.isEmpty ? 'לא הוזן' : email),
                // Provider-only fields
                if (isProvider) ...[
                  _detailRow('קטגוריה',
                      serviceType.isEmpty ? 'לא הוגדרה' : '$serviceType${subCategory.isNotEmpty ? ' › $subCategory' : ''}'),
                  _detailRow('מדיניות ביטול', _policyCopy(cancellationPolicy)),
                ],
                _detailRow('יתרה', '₪${balance.toStringAsFixed(2)}'),
                if (isProvider)
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
                  createdAt != null
                      ? '${_fmt.format(createdAt)} (${_relativeTime(createdAt)})'
                      : 'לא ידוע',
                  _kGreen,
                ),
                _timelineItem(
                  Icons.wifi_rounded,
                  'נראה לאחרונה',
                  lastOnline != null
                      ? '${_fmt.format(lastOnline)} (${_relativeTime(lastOnline)})'
                      : 'לא ידוע',
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

  // ── Compute live rating from reviews (fallback when user doc is stale) ──

  double _liveRating(List<Map<String, dynamic>> reviews) {
    if (reviews.isEmpty) return 0;
    double total = 0;
    int count = 0;
    for (final r in reviews) {
      final v = (r['overallRating'] ?? r['rating']) as num?;
      if (v != null && v > 0) {
        total += v.toDouble();
        count++;
      }
    }
    return count > 0 ? total / count : 0;
  }

  // ── Trust score from jobs ─────────────────────────────────────────────

  /// Returns (completedCount, cancelledCount, trustPercent).
  (int, int, double) _trustScore(List<Map<String, dynamic>> jobs) {
    int completed = 0, cancelled = 0;
    for (final j in jobs) {
      final s = j['status'] as String? ?? '';
      if (s == 'completed') completed++;
      if (s.startsWith('cancelled')) cancelled++;
    }
    final total = completed + cancelled;
    final pct = total > 0 ? (completed / total * 100) : -1.0; // -1 = no data
    return (completed, cancelled, pct);
  }

  Color _trustColor(double pct) {
    if (pct < 0) return _kMuted;
    if (pct >= 90) return _kGreen;
    if (pct >= 70) return _kAmber;
    return _kRed;
  }

  // ── Provider stats — Earning Power ──────────────────────────────────

  Widget _buildProviderStats(Map<String, dynamic> data) {
    final firestoreRating = (data['rating'] as num? ?? 0).toDouble();
    final xp = (data['xp'] as num? ?? 0).toInt();

    final txAsync = ref.watch(userTransactionsProvider(widget.userId));
    final jobsAsync = ref.watch(userJobsProvider(widget.userId));
    final reviewsAsync = ref.watch(userReviewsProvider(widget.userId));

    final reviews = reviewsAsync.valueOrNull ?? [];
    final jobs = jobsAsync.valueOrNull ?? [];
    final jobCount = jobs.length;
    final reviewCount = reviews.length;
    final rating = firestoreRating > 0 ? firestoreRating : _liveRating(reviews);
    final (_, _, trustPct) = _trustScore(jobs);

    final totalEarned = txAsync.valueOrNull
            ?.where((tx) => tx['receiverId'] == widget.userId)
            .fold<double>(
                0, (acc, tx) => acc + ((tx['amount'] as num?) ?? 0).toDouble()) ??
        0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text('כוח הרווחה',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _kMuted)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _miniStatCard(
                  'הכנסות', '₪${totalEarned.toStringAsFixed(0)}',
                  Icons.account_balance_wallet_rounded, _kGreen),
              _miniStatCard(
                  'עבודות', '$jobCount',
                  Icons.work_outline_rounded, _kPurple),
              _miniStatCard(
                  'דירוג',
                  rating > 0 ? rating.toStringAsFixed(1) : '—',
                  Icons.star_rounded, _kAmber),
              _miniStatCard(
                  'אמינות',
                  trustPct < 0 ? '—' : '${trustPct.toStringAsFixed(0)}%',
                  Icons.verified_user_rounded,
                  _trustColor(trustPct)),
              GestureDetector(
                onTap: _showReviewsSheet,
                child: _miniStatCard(
                    'ביקורות', '$reviewCount',
                    Icons.rate_review_rounded, const Color(0xFFEC4899)),
              ),
              _miniStatCard('XP', '$xp', Icons.bolt_rounded, _kIndigo),
            ],
          ),
        ],
      ),
    );
  }

  // ── Customer stats — Buying Power ─────────────────────────────────────

  Widget _buildCustomerStats(Map<String, dynamic> data) {
    final firestoreCustRating =
        (data['customerRating'] as num? ?? 0).toDouble();

    final txAsync = ref.watch(userTransactionsProvider(widget.userId));
    final jobsAsync = ref.watch(userJobsProvider(widget.userId));
    final reviewsAsync = ref.watch(userReviewsProvider(widget.userId));

    final reviews = reviewsAsync.valueOrNull ?? [];
    final jobs = jobsAsync.valueOrNull ?? [];
    final bookingCount = jobs.length;
    final reviewCount = reviews.length;
    final customerRating = firestoreCustRating > 0
        ? firestoreCustRating
        : _liveRating(reviews);
    final (_, _, trustPct) = _trustScore(jobs);

    final totalSpent = txAsync.valueOrNull
            ?.where((tx) => tx['senderId'] == widget.userId)
            .fold<double>(
                0, (acc, tx) => acc + ((tx['amount'] as num?) ?? 0).toDouble()) ??
        0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text('כוח הקנייה',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _kMuted)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _miniStatCard(
                  'הוצאות', '₪${totalSpent.toStringAsFixed(0)}',
                  Icons.shopping_cart_rounded, _kIndigo),
              _miniStatCard(
                  'הזמנות', '$bookingCount',
                  Icons.calendar_today_rounded, _kPurple),
              _miniStatCard(
                  'דירוג לקוח',
                  customerRating > 0
                      ? customerRating.toStringAsFixed(1)
                      : '—',
                  Icons.star_rounded, _kAmber),
              _miniStatCard(
                  'אמינות',
                  trustPct < 0 ? '—' : '${trustPct.toStringAsFixed(0)}%',
                  Icons.verified_user_rounded,
                  _trustColor(trustPct)),
              GestureDetector(
                onTap: _showReviewsSheet,
                child: _miniStatCard(
                    'ביקורות', '$reviewCount',
                    Icons.rate_review_rounded, const Color(0xFFEC4899)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatCard(
      String label, String value, IconData icon, Color color) {
    return SizedBox(
      width: 75,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
      ),
    );
  }

  // ── Reviews bottom sheet ───────────────────────────────────────────────

  void _showReviewsSheet() {
    final reviewsAsync = ref.read(userReviewsProvider(widget.userId));
    final allReviews = reviewsAsync.valueOrNull ?? [];
    final userAsync = ref.read(userDetailProvider(widget.userId));
    final isProvider = userAsync.valueOrNull?['isProvider'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        bool blindOnly = false;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final reviews = blindOnly
                ? allReviews.where((r) {
                    final published = r['isPublished'] as bool? ?? false;
                    final created =
                        ((r['createdAt'] ?? r['timestamp']) as Timestamp?)
                            ?.toDate();
                    final expired = created != null &&
                        DateTime.now().difference(created).inDays >= 7;
                    return !published && !expired;
                  }).toList()
                : allReviews;

            final blindCount = allReviews.where((r) {
              final published = r['isPublished'] as bool? ?? false;
              final created =
                  ((r['createdAt'] ?? r['timestamp']) as Timestamp?)
                      ?.toDate();
              final expired = created != null &&
                  DateTime.now().difference(created).inDays >= 7;
              return !published && !expired;
            }).length;

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) => Column(
                children: [
                  // Handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10))),
                  ),
                  // Title row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.rate_review_rounded,
                            color: _kIndigo, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              isProvider
                                  ? 'ביקורות מלקוחות (${reviews.length})'
                                  : 'ביקורות מנותני שירות (${reviews.length})',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _kDark)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Filter toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () =>
                              setSheetState(() => blindOnly = !blindOnly),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: blindOnly
                                  ? _kAmber.withValues(alpha: 0.15)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: blindOnly
                                      ? _kAmber.withValues(alpha: 0.4)
                                      : Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  blindOnly
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 14,
                                  color: blindOnly ? _kAmber : _kMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'מוסתרות בלבד ($blindCount)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: blindOnly ? _kAmber : _kMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kIndigo.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('תצוגת אדמין',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _kIndigo,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  // Review list
                  Expanded(
                    child: reviews.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    blindOnly
                                        ? Icons.visibility_off_outlined
                                        : Icons.rate_review_outlined,
                                    size: 48,
                                    color: _kMuted),
                                const SizedBox(height: 12),
                                Text(
                                    blindOnly
                                        ? 'אין ביקורות מוסתרות'
                                        : 'אין ביקורות עדיין',
                                    style: const TextStyle(
                                        color: _kMuted, fontSize: 15)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: reviews.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 20),
                            itemBuilder: (_, i) =>
                                _buildReviewItem(reviews[i]),
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

  Widget _buildReviewItem(Map<String, dynamic> review) {
    final reviewerName = review['reviewerName'] as String? ?? 'משתמש';
    final isClientReview = review['isClientReview'] == true;
    final overall =
        (review['overallRating'] ?? review['rating'] as num? ?? 0)
            .toDouble();
    final comment = (review['publicComment'] ?? review['comment'])
            as String? ??
        '';
    final privateComment =
        review['privateAdminComment'] as String? ?? '';
    final isPublished = review['isPublished'] as bool? ?? false;
    final createdAt =
        ((review['createdAt'] ?? review['timestamp']) as Timestamp?)
            ?.toDate();

    // 7-day blind logic: published if isPublished==true OR 7+ days old
    final bool effectivelyPublic = isPublished ||
        (createdAt != null &&
            DateTime.now().difference(createdAt).inDays >= 7);

    // Rating params breakdown
    final ratingParams =
        review['ratingParams'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: effectivelyPublic
            ? Colors.white
            : _kAmber.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: effectivelyPublic
              ? Colors.grey.shade100
              : _kAmber.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: reviewer name + status badge + date
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isClientReview
                    ? _kIndigo.withValues(alpha: 0.1)
                    : _kGreen.withValues(alpha: 0.1),
                child: Icon(
                  isClientReview
                      ? Icons.person_rounded
                      : Icons.work_rounded,
                  size: 16,
                  color: isClientReview ? _kIndigo : _kGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reviewerName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _kDark)),
                    Text(
                      isClientReview
                          ? 'ביקורת לקוח'
                          : 'ביקורת ספק',
                      style: const TextStyle(
                          fontSize: 11, color: _kMuted),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: effectivelyPublic
                      ? _kGreen.withValues(alpha: 0.1)
                      : _kAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: effectivelyPublic
                        ? _kGreen.withValues(alpha: 0.3)
                        : _kAmber.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  effectivelyPublic ? 'פומבי' : 'מוסתר מהמשתמש',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: effectivelyPublic ? _kGreen : _kAmber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Star rating
          Row(
            children: [
              ...List.generate(5, (i) {
                final starVal = i + 1;
                return Icon(
                  starVal <= overall
                      ? Icons.star_rounded
                      : (starVal - 0.5 <= overall
                          ? Icons.star_half_rounded
                          : Icons.star_border_rounded),
                  color: _kAmber,
                  size: 20,
                );
              }),
              const SizedBox(width: 6),
              Text(overall.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _kDark)),
              if (createdAt != null) ...[
                const Spacer(),
                Text(_fmt.format(createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: _kMuted)),
              ],
            ],
          ),

          // Rating params breakdown (admin detail)
          if (ratingParams.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ratingParams.entries.map((e) {
                final paramLabel = _ratingParamLabel(e.key);
                final val = (e.value as num?)?.toDouble() ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$paramLabel: ${val.toStringAsFixed(1)}',
                    style: const TextStyle(
                        fontSize: 10, color: _kMuted),
                  ),
                );
              }).toList(),
            ),
          ],

          // Comment
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment,
                style: const TextStyle(
                    fontSize: 13, color: _kDark, height: 1.5)),
          ],

          // Private admin comment
          if (privateComment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _kRed.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 14, color: _kRed),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      privateComment,
                      style: const TextStyle(
                          fontSize: 12, color: _kRed, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _ratingParamLabel(String key) {
    switch (key) {
      case 'professional':
        return 'מקצועיות';
      case 'timing':
        return 'דיוק בזמנים';
      case 'communication':
        return 'תקשורת';
      case 'value':
        return 'תמורה למחיר';
      default:
        return key;
    }
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

  // ── Hebrew relative time ────────────────────────────────────────────────

  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 365) {
      final y = (diff.inDays / 365).floor();
      return y == 1 ? 'לפני שנה' : 'לפני $y שנים';
    } else if (diff.inDays >= 30) {
      final m = (diff.inDays / 30).floor();
      return m == 1 ? 'לפני חודש' : 'לפני $m חודשים';
    } else if (diff.inDays >= 1) {
      return diff.inDays == 1 ? 'אתמול' : 'לפני ${diff.inDays} ימים';
    } else if (diff.inHours >= 1) {
      return 'לפני ${diff.inHours} שעות';
    } else {
      return 'לפני ${diff.inMinutes} דקות';
    }
  }

  // ── Hebrew cancellation policy label ───────────────────────────────────

  static String _policyCopy(String policy) {
    switch (policy) {
      case 'flexible':
        return 'גמישה (4 שעות)';
      case 'moderate':
        return 'מתונה (24 שעות)';
      case 'strict':
        return 'קפדנית (48 שעות)';
      default:
        return policy;
    }
  }

  // ── Fix profile image — writes Auth photoURL to Firestore ──────────────

  Future<void> _fixProfileImage(Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);

    // Try the viewed user's own Auth record isn't accessible from admin,
    // so we fetch their Google photoURL from the data we have.
    // If it's the current admin viewing their OWN profile, use Auth directly.
    final currentUser = FirebaseAuth.instance.currentUser;
    String? photoUrl;

    if (currentUser?.uid == widget.userId) {
      // Admin viewing their own detail page — use Auth
      await currentUser!.reload();
      photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    }

    if (photoUrl == null || photoUrl.isEmpty) {
      // Try any fallback fields from the Firestore doc
      photoUrl = _pickString(data, ['photoURL', 'imageUrl', 'photo']);
    }

    if (photoUrl.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('לא נמצאה תמונה לסנכרון — העלה תמונה דרך עריכת פרופיל'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'profileImage': photoUrl});

    _logAuditAction('סנכרון תמונת פרופיל', data['name'] ?? 'משתמש');

    messenger.showSnackBar(const SnackBar(
      content: Text('תמונת פרופיל עודכנה'),
      backgroundColor: Color(0xFF10B981),
    ));
  }

  // ── Speed Dial FAB ──────────────────────────────────────────────────────

  bool _fabOpen = false;

  Widget _buildSpeedDial(Map<String, dynamic> data) {
    final phone = _pickString(data, ['phone', 'phoneNumber', 'mobile']);
    final adminNote = _pickString(data, ['adminNote']);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Expandable actions
        if (_fabOpen) ...[
          // WhatsApp
          if (phone.isNotEmpty)
            _fabAction(
              icon: Icons.chat_rounded,
              label: 'WhatsApp',
              color: const Color(0xFF25D366),
              onTap: () {
                final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
                final waNum = cleaned.startsWith('+')
                    ? cleaned.substring(1)
                    : cleaned.startsWith('0')
                        ? '972${cleaned.substring(1)}'
                        : cleaned;
                launchUrl(Uri.parse('https://wa.me/$waNum'));
              },
            ),
          // Call
          if (phone.isNotEmpty)
            _fabAction(
              icon: Icons.phone_rounded,
              label: 'חייג',
              color: _kGreen,
              onTap: () => launchUrl(Uri.parse('tel:$phone')),
            ),
          // Internal note
          _fabAction(
            icon: Icons.edit_note_rounded,
            label: 'הערה פנימית',
            color: _kAmber,
            onTap: () {
              setState(() => _fabOpen = false);
              _showEditNoteDialog(adminNote);
            },
          ),
          // Send notification
          _fabAction(
            icon: Icons.notifications_active_rounded,
            label: 'שלח התראה',
            color: _kIndigo,
            onTap: () {
              setState(() => _fabOpen = false);
              _showSendNotificationDialog(data);
            },
          ),
          const SizedBox(height: 8),
        ],
        // Main FAB
        FloatingActionButton(
          backgroundColor: _fabOpen ? _kRed : _kIndigo,
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _fabOpen ? Icons.close_rounded : Icons.bolt_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fabAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6),
              ],
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            heroTag: 'fab_$label',
            backgroundColor: color,
            onPressed: onTap,
            child: Icon(icon, color: Colors.white, size: 20),
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
