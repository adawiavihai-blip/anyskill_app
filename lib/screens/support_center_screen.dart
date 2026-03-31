/// AnySkill — Support & Dispute Center (Wolt/Airbnb-inspired)
///
/// Two-phase flow:
///   1. Category grid → self-service tips for common issues
///   2. "Start Live Chat" → creates support_ticket + opens chat UI
///
/// Optional [jobId] pre-fills context when opened from a booking/chat.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportCenterScreen extends StatefulWidget {
  /// If provided, the ticket is pre-linked to this job.
  final String? jobId;
  final String? jobCategory;

  const SupportCenterScreen({super.key, this.jobId, this.jobCategory});

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  static final _db = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _userName =
      FirebaseAuth.instance.currentUser?.displayName ?? 'משתמש';

  String? _selectedCategory;
  bool _showSelfService = false;
  bool _creatingTicket = false;

  // ── Category definitions ───────────────────────────────────────────────

  static const _categories = [
    _SupportCategory(
      id: 'payments',
      nameHe: 'תשלומים ועמלות',
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF6366F1),
    ),
    _SupportCategory(
      id: 'volunteer',
      nameHe: 'התנדבות וקהילה',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFF10B981),
    ),
    _SupportCategory(
      id: 'account',
      nameHe: 'חשבון ופרופיל',
      icon: Icons.person_rounded,
      color: Color(0xFF8B5CF6),
    ),
    _SupportCategory(
      id: 'other',
      nameHe: 'בעיה אחרת',
      icon: Icons.help_outline_rounded,
      color: Color(0xFFF59E0B),
    ),
  ];

  // ── Self-service tips per category ─────────────────────────────────────

  static const Map<String, List<_SelfServiceTip>> _selfServiceTips = {
    'payments': [
      _SelfServiceTip(
        titleHe: 'התשלום לא שוחרר?',
        bodyHe: 'תשלומים משוחררים רק לאחר שהלקוח לוחץ "אשר ושחרר". '
            'אם הלקוח לא אישר תוך 48 שעות, פנה אלינו.',
        icon: Icons.lock_clock,
      ),
      _SelfServiceTip(
        titleHe: 'רוצה ביטול והחזר?',
        bodyHe: 'ביטול לפני מועד השירות = החזר מלא. '
            'אחרי — לפי מדיניות הביטול של הספק (גמיש/מתון/קשיח).',
        icon: Icons.replay,
      ),
      _SelfServiceTip(
        titleHe: 'עמלה גבוהה מדי?',
        bodyHe: 'עמלת הפלטפורמה נקבעת על ידי ההנהלה. '
            'תוכל לראות את האחוז המדויק בעמוד הפרופיל.',
        icon: Icons.percent,
      ),
    ],
    'volunteer': [
      _SelfServiceTip(
        titleHe: 'המתנדב לא הגיע?',
        bodyHe: 'ודא שהמתנדב אימת מיקום באמצעות GPS (כפתור "הגעתי"). '
            'אם לא — אל תאשר את ההתנדבות.',
        icon: Icons.location_off,
      ),
      _SelfServiceTip(
        titleHe: 'לא קיבלתי XP',
        bodyHe: 'XP מוענק רק לאחר שהלקוח אישר את ההתנדבות. '
            'ודא שהלקוח לחץ "אשר סיום" בצ\'אט.',
        icon: Icons.star_border,
      ),
    ],
    'account': [
      _SelfServiceTip(
        titleHe: 'רוצה לשנות קטגוריה?',
        bodyHe: 'עבור להגדרות > ערוך פרופיל > שנה את סוג השירות.',
        icon: Icons.category,
      ),
      _SelfServiceTip(
        titleHe: 'רוצה למחוק חשבון?',
        bodyHe: 'עבור לפרופיל > הגדרות > מחק חשבון. '
            'לאחר המחיקה לא ניתן לשחזר נתונים.',
        icon: Icons.delete_forever,
      ),
    ],
    'other': [
      _SelfServiceTip(
        titleHe: 'בעיה טכנית?',
        bodyHe: 'נסה לרענן את האפליקציה. '
            'אם הבעיה נמשכת — פתח פנייה ונטפל בזה.',
        icon: Icons.refresh,
      ),
    ],
  };

  // ── Ticket Creation ────────────────────────────────────────────────────

  Future<void> _createTicket(String subject) async {
    if (_uid.isEmpty || _selectedCategory == null) return;
    setState(() => _creatingTicket = true);

    try {
      final ticketRef = await _db.collection('support_tickets').add({
        'userId': _uid,
        'userName': _userName,
        'jobId': widget.jobId,
        'category': _selectedCategory,
        'subject': subject,
        'status': 'open',
        'evidenceUrls': <String>[],
        'assignedAdmin': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Write initial user message
      await ticketRef.collection('messages').add({
        'senderId': _uid,
        'senderName': _userName,
        'isAdmin': false,
        'message': subject,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      // Navigate to ticket chat
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _TicketChatScreen(
            ticketId: ticketRef.id,
            category: _selectedCategory!,
            isAdmin: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingTicket = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text('מרכז התמיכה',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _showSelfService && _selectedCategory != null
          ? _buildSelfServicePhase()
          : _buildCategoryGrid(),
    );
  }

  // ── Phase 1: Category Grid ─────────────────────────────────────────────

  Widget _buildCategoryGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          const Text(
            'איך נוכל לעזור?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'בחרו קטגוריה כדי למצוא פתרון מהיר',
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),

          // ── Estimated response time (Wolt-style) ────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: Color(0xFF6366F1)),
                SizedBox(width: 6),
                Text(
                  'זמן תגובה משוער: 5 דקות',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Category grid ───────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.3,
            children: _categories.map((cat) => _buildCategoryCard(cat)).toList(),
          ),

          // ── Pre-filled context banner ───────────────────────────────
          if (widget.jobId != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 18, color: Color(0xFF10B981)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'הפנייה מקושרת להזמנה #${widget.jobId!.substring(0, 8)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── My open tickets ─────────────────────────────────────────
          if (_uid.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text(
              'הפניות שלי',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 10),
            _buildMyTickets(),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryCard(_SupportCategory cat) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = cat.id;
          _showSelfService = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(cat.icon, color: cat.color, size: 22),
            ),
            const Spacer(),
            Text(
              cat.nameHe,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyTickets() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('support_tickets')
          .where('userId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('אין פניות פתוחות',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
            ),
          );
        }

        return Column(
          children: snap.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>? ?? {};
            final status = d['status'] as String? ?? 'open';
            final subject = d['subject'] as String? ?? '';
            final category = d['category'] as String? ?? '';
            final isOpen = status == 'open' || status == 'in_progress';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOpen
                      ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isOpen
                      ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                      : const Color(0xFF10B981).withValues(alpha: 0.1),
                  child: Icon(
                    isOpen ? Icons.chat_bubble_outline : Icons.check_circle,
                    color: isOpen
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                title: Text(
                  subject.length > 40
                      ? '${subject.substring(0, 40)}...'
                      : subject,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _categoryLabel(category),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
                trailing: _statusChip(status),
                onTap: isOpen
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _TicketChatScreen(
                              ticketId: doc.id,
                              category: category,
                              isAdmin: false,
                            ),
                          ),
                        )
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ── Phase 2: Self-Service Tips + Escalate ──────────────────────────────

  Widget _buildSelfServicePhase() {
    final tips = _selfServiceTips[_selectedCategory] ?? [];
    final cat = _categories.firstWhere((c) => c.id == _selectedCategory);
    final subjectCtrl = TextEditingController();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          GestureDetector(
            onTap: () => setState(() => _showSelfService = false),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF6366F1)),
                SizedBox(width: 4),
                Text('חזרה לקטגוריות',
                    style: TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Category header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(cat.icon, color: cat.color, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                cat.nameHe,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),

          // Self-service tips
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'אולי זה יעזור:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 10),
            ...tips.map((tip) => _buildTipCard(tip)),
          ],

          // Escalation section
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'לא מצאת פתרון? דבר איתנו',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'תאר/י בקצרה את הבעיה ונחזור אליך תוך דקות',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: subjectCtrl,
                  textAlign: TextAlign.start,
                  textDirection: TextDirection.rtl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'תאר/י את הבעיה...',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF6366F1), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: _creatingTicket
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text('התחל שיחה עם התמיכה',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _creatingTicket
                        ? null
                        : () {
                            final text = subjectCtrl.text.trim();
                            if (text.length < 5) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('נא לתאר את הבעיה (לפחות 5 תווים)'),
                                ),
                              );
                              return;
                            }
                            _createTicket(text);
                          },
                  ),
                ),

                // Response time badge
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'זמן תגובה משוער: 5 דקות',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(_SelfServiceTip tip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.titleHe,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip.bodyHe,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tip.icon, color: const Color(0xFF6366F1), size: 18),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _categoryLabel(String id) {
    return _categories
        .where((c) => c.id == id)
        .map((c) => c.nameHe)
        .firstOrNull ?? id;
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'open'        => ('פתוח', const Color(0xFFF59E0B)),
      'in_progress' => ('בטיפול', const Color(0xFF6366F1)),
      'resolved'    => ('נפתר', const Color(0xFF10B981)),
      _             => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TICKET CHAT SCREEN (shared by user + admin)
// ═══════════════════════════════════════════════════════════════════════════════

class TicketChatScreen extends _TicketChatScreen {
  const TicketChatScreen({
    super.key,
    required super.ticketId,
    required super.category,
    required super.isAdmin,
  });
}

class _TicketChatScreen extends StatefulWidget {
  final String ticketId;
  final String category;
  final bool isAdmin;

  const _TicketChatScreen({
    super.key,
    required this.ticketId,
    required this.category,
    required this.isAdmin,
  });

  @override
  State<_TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<_TicketChatScreen> {
  static final _db = FirebaseFirestore.instance;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _userName =
      FirebaseAuth.instance.currentUser?.displayName ?? 'תמיכה';
  bool _sending = false;

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      await _db
          .collection('support_tickets')
          .doc(widget.ticketId)
          .collection('messages')
          .add({
        'senderId': _uid,
        'senderName': widget.isAdmin ? 'צוות AnySkill' : _userName,
        'isAdmin': widget.isAdmin,
        'message': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update ticket timestamp + status
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (widget.isAdmin) {
        updates['status'] = 'in_progress';
      }
      await _db
          .collection('support_tickets')
          .doc(widget.ticketId)
          .update(updates);
    } catch (e) {
      debugPrint('[TicketChat] send error: $e');
    }

    if (mounted) setState(() => _sending = false);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text('שיחה עם התמיכה',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              '#${widget.ticketId.substring(0, 8)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        actions: widget.isAdmin
            ? [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) => _handleAdminAction(val),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'resolve',
                        child: Text('✓ סמן כנפתר')),
                    const PopupMenuItem(
                        value: 'xp_comp',
                        child: Text('🎁 פיצוי XP (+100)')),
                  ],
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // ── Response time banner ────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: const Color(0xFF6366F1).withValues(alpha: 0.05),
            child: const Text(
              'זמן תגובה משוער: 5 דקות',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6366F1),
              ),
            ),
          ),

          // ── Messages list ───────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('support_tickets')
                  .doc(widget.ticketId)
                  .collection('messages')
                  .orderBy('createdAt')
                  .limit(100)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(
                        _scrollCtrl.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>? ?? {};
                    final isAdmin = d['isAdmin'] == true;
                    final isMe = d['senderId'] == _uid;
                    final msg = d['message'] as String? ?? '';
                    final name = d['senderName'] as String? ?? '';

                    return Align(
                      alignment: isMe
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFF6366F1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(
                                isAdmin ? '🛡️ $name' : name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isAdmin
                                      ? const Color(0xFF6366F1)
                                      : const Color(0xFF9CA3AF),
                                ),
                              ),
                            if (!isMe) const SizedBox(height: 4),
                            Text(
                              msg,
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    isMe ? Colors.white : const Color(0xFF1A1A2E),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ── Input area ──────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: 'כתוב הודעה...',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      filled: true,
                      fillColor: const Color(0xFFF4F7F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6366F1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAdminAction(String action) async {
    final ticketRef = _db.collection('support_tickets').doc(widget.ticketId);

    switch (action) {
      case 'resolve':
        await ticketRef.update({
          'status': 'resolved',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // Send system message
        await ticketRef.collection('messages').add({
          'senderId': _uid,
          'senderName': 'מערכת',
          'isAdmin': true,
          'message': '✅ הפנייה סומנה כנפתרה. תודה!',
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ הפנייה נפתרה'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      case 'xp_comp':
        final ticketDoc = await ticketRef.get();
        final userId = (ticketDoc.data()?['userId'] as String?) ?? '';
        if (userId.isNotEmpty) {
          await _db.collection('users').doc(userId).update({
            'xp': FieldValue.increment(100),
          });
          await ticketRef.collection('messages').add({
            'senderId': _uid,
            'senderName': 'מערכת',
            'isAdmin': true,
            'message': '🎁 קיבלת פיצוי של +100 XP. מצטערים על אי-הנוחות!',
            'createdAt': FieldValue.serverTimestamp(),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✓ פיצוי XP (+100) הוענק'),
                backgroundColor: Color(0xFF6366F1),
              ),
            );
          }
        }
    }
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _SupportCategory {
  final String id;
  final String nameHe;
  final IconData icon;
  final Color color;
  const _SupportCategory({
    required this.id,
    required this.nameHe,
    required this.icon,
    required this.color,
  });
}

class _SelfServiceTip {
  final String titleHe;
  final String bodyHe;
  final IconData icon;
  const _SelfServiceTip({
    required this.titleHe,
    required this.bodyHe,
    required this.icon,
  });
}
