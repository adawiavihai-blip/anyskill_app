/// AnyTasks 3.0 — Task Detail Screen
///
/// Shows full task details with role-aware action buttons:
///   Creator: confirm, dispute, cancel
///   Provider: claim, start work, submit proof
///   Both: chat link, status timeline
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/anytask.dart';
import '../services/anytask_service.dart';
import '../services/anytask_category_service.dart';
import '../widgets/anytask_status_badge.dart';
import '../widgets/anytask_proof_sheet.dart';
import 'chat_screen.dart';

class AnytaskDetailScreen extends StatefulWidget {
  final String taskId;
  const AnytaskDetailScreen({super.key, required this.taskId});

  @override
  State<AnytaskDetailScreen> createState() => _AnytaskDetailScreenState();
}

class _AnytaskDetailScreenState extends State<AnytaskDetailScreen> {
  static const _kIndigo = Color(0xFF6366F1);
  static const _kDark   = Color(0xFF1A1A2E);
  static const _kMuted  = Color(0xFF6B7280);
  static const _kGreen  = Color(0xFF10B981);
  static const _kRed    = Color(0xFFEF4444);
  static const _kAmber  = Color(0xFFF59E0B);

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _acting = false;

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _claimTask(AnyTask task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    final userData = userDoc.data() ?? {};

    setState(() => _acting = true);
    final err = await AnytaskService.claimTask(
      taskId: task.id,
      providerId: user.uid,
      providerName: userData['name'] as String? ?? user.displayName ?? '',
      providerImage: userData['profileImage'] as String?,
    );
    if (mounted) setState(() => _acting = false);

    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: _kRed),
      );
    }
  }

  Future<void> _startWork(AnyTask task) async {
    setState(() => _acting = true);
    final err = await AnytaskService.startWork(task.id, _uid);
    if (mounted) setState(() => _acting = false);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: _kRed),
      );
    }
  }

  Future<void> _submitProof(AnyTask task) async {
    final result = await AnytaskProofSheet.show(
      context,
      taskId: task.id,
      taskTitle: task.title,
    );
    if (result == null) return;

    setState(() => _acting = true);
    final err = await AnytaskService.submitProof(
      taskId: task.id,
      providerId: _uid,
      proofPhotoUrl: result.photoUrl,
      proofText: result.text,
    );
    if (mounted) setState(() => _acting = false);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: _kRed),
      );
    }
  }

  Future<void> _confirmCompletion(AnyTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('אישור השלמה'),
        content: const Text('האם המשימה הושלמה לשביעות רצונך? התשלום ישוחרר לנותן השירות.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
            child: const Text('אשר ושחרר תשלום', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acting = true);
    final err = await AnytaskService.confirmCompletion(task.id, _uid);
    if (mounted) setState(() => _acting = false);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: _kRed),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('התשלום שוחרר בהצלחה! 💰'), backgroundColor: _kGreen),
      );
    }
  }

  Future<void> _openDispute(AnyTask task) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('פתיחת מחלוקת'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('תאר את הבעיה (לפחות 10 תווים)'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'למה ההוכחה לא מספקת?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, reasonCtrl.text),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: const Text('פתח מחלוקת', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null || reason.trim().length < 10) return;

    setState(() => _acting = true);
    final err = await AnytaskService.openDispute(taskId: task.id, creatorId: _uid, reason: reason);
    if (mounted) setState(() => _acting = false);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: _kRed),
      );
    }
  }

  Future<void> _cancelTask(AnyTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ביטול משימה'),
        content: const Text('האם אתה בטוח? עלול לחול קנס ביטול.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('חזור')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            child: const Text('בטל משימה', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acting = true);
    final err = await AnytaskService.cancelTask(taskId: task.id, cancelledBy: _uid);
    if (mounted) setState(() => _acting = false);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: _kRed),
      );
    }
  }

  void _openChat(AnyTask task) {
    if (task.chatRoomId == null || task.chatRoomId!.isEmpty) return;
    final receiverId = _uid == task.creatorId ? task.providerId : task.creatorId;
    final receiverName = _uid == task.creatorId ? task.providerName : task.creatorName;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          receiverId: receiverId ?? '',
          receiverName: receiverName ?? '',
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text('פרטי משימה'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _kDark,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: AnytaskService.streamTask(widget.taskId),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('שגיאה בטעינת המשימה'));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final task = AnyTask.fromFirestore(snap.data!);
          final isCreator  = _uid == task.creatorId;
          final isProvider = _uid == task.providerId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(task),
                const SizedBox(height: 16),
                _buildDescriptionCard(task),
                const SizedBox(height: 12),
                _buildDetailsCard(task),
                if (task.hasProof) ...[
                  const SizedBox(height: 12),
                  _buildProofCard(task),
                ],
                if (task.chatRoomId != null && task.chatRoomId!.isNotEmpty && (isCreator || isProvider)) ...[
                  const SizedBox(height: 12),
                  _buildChatButton(task),
                ],
                const SizedBox(height: 16),
                _buildActions(task, isCreator, isProvider),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(AnyTask task) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kIndigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AnytaskCategoryService.iconFor(task.category), size: 14, color: _kIndigo),
                    const SizedBox(width: 4),
                    Text(
                      AnytaskCategoryService.labelHe(task.category),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kIndigo),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AnytaskStatusBadge(status: task.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(task.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kGreen, Color(0xFF059669)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '₪${task.amount.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          // Auto-release timer
          if (task.status == AnyTaskStatus.proofSubmitted && task.hoursUntilAutoRelease != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kAmber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_rounded, size: 18, color: _kAmber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'שחרור אוטומטי בעוד ${task.hoursUntilAutoRelease!.toStringAsFixed(0)} שעות',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kAmber),
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

  Widget _buildDescriptionCard(AnyTask task) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('תיאור', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 8),
          Text(task.description, style: const TextStyle(fontSize: 14, color: _kMuted, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(AnyTask task) {
    return _card(
      child: Column(
        children: [
          if (task.locationText != null && task.locationText!.isNotEmpty)
            _detailRow(Icons.location_on_outlined, 'מיקום', task.locationText!),
          if (task.deadline != null)
            _detailRow(Icons.schedule_rounded, 'דדליין',
                '${task.deadline!.day}/${task.deadline!.month}/${task.deadline!.year} ${task.deadline!.hour}:${task.deadline!.minute.toString().padLeft(2, '0')}'),
          _detailRow(Icons.camera_alt_outlined, 'הוכחה נדרשת',
              task.proofType == 'photo' ? 'תמונה' : task.proofType == 'text' ? 'טקסט' : 'תמונה + טקסט'),
          if (task.providerName != null)
            _detailRow(Icons.person_rounded, 'נותן שירות', task.providerName!),
          _detailRow(Icons.person_outline_rounded, 'מפרסם', task.creatorName),
        ],
      ),
    );
  }

  Widget _buildProofCard(AnyTask task) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, size: 18, color: _kGreen),
              SizedBox(width: 6),
              Text('הוכחת ביצוע', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kDark)),
            ],
          ),
          const SizedBox(height: 10),
          if (task.proofPhotoUrl != null && task.proofPhotoUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                task.proofPhotoUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  color: Colors.grey[200],
                  child: const Center(child: Icon(Icons.broken_image, color: _kMuted)),
                ),
              ),
            ),
          if (task.proofText != null && task.proofText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.proofText!, style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildChatButton(AnyTask task) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => _openChat(task),
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: const Text('שלח הודעה', style: TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kIndigo,
          side: const BorderSide(color: _kIndigo),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildActions(AnyTask task, bool isCreator, bool isProvider) {
    if (_acting) {
      return const Center(child: CircularProgressIndicator());
    }

    final buttons = <Widget>[];

    // ── Provider actions ─────────────────────────────────────────────
    if (!isCreator && task.status == AnyTaskStatus.open) {
      buttons.add(_actionButton('תפוס משימה! 🎯', _kIndigo, () => _claimTask(task)));
    }
    if (isProvider && task.status == AnyTaskStatus.claimed) {
      buttons.add(_actionButton('התחל עבודה 🛠️', _kIndigo, () => _startWork(task)));
    }
    if (isProvider && (task.status == AnyTaskStatus.inProgress || task.status == AnyTaskStatus.claimed)) {
      buttons.add(_actionButton('שלח הוכחה 📸', _kGreen, () => _submitProof(task)));
    }

    // ── Creator actions ──────────────────────────────────────────────
    if (isCreator && task.status == AnyTaskStatus.proofSubmitted) {
      buttons.add(_actionButton('אשר ושחרר תשלום ✅', _kGreen, () => _confirmCompletion(task)));
      buttons.add(const SizedBox(height: 8));
      buttons.add(_actionButton('פתח מחלוקת ⚠️', _kRed, () => _openDispute(task)));
    }

    // ── Cancel (both roles, non-terminal) ────────────────────────────
    if ((isCreator || isProvider) && task.isActive && task.status != AnyTaskStatus.proofSubmitted) {
      buttons.add(const SizedBox(height: 8));
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => _cancelTask(task),
            child: const Text('בטל משימה', style: TextStyle(color: _kMuted, fontSize: 14)),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Column(children: buttons);
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: child,
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kIndigo),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kDark)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: _kMuted))),
        ],
      ),
    );
  }
}
