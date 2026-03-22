import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';

class PendingVerificationScreen extends StatefulWidget {
  const PendingVerificationScreen({super.key});

  @override
  State<PendingVerificationScreen> createState() =>
      _PendingVerificationScreenState();
}

class _PendingVerificationScreenState
    extends State<PendingVerificationScreen> {
  StreamSubscription<DocumentSnapshot>? _userSub;

  @override
  void initState() {
    super.initState();
    _listenForApproval();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  /// Watch the user's Firestore doc. The moment isVerified flips to true,
  /// navigate straight to HomeScreen without requiring a manual re-login.
  void _listenForApproval() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final data = doc.data() ?? {};
      if (data['isVerified'] == true) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 28),

              // Title
              const Text(
                'הפרופיל שלך בבדיקה',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F1F33),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'תקבל/י אימייל ברגע שהפרופיל יאושר',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 28),

              // Steps card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _step(
                      icon: Icons.upload_file_rounded,
                      color: const Color(0xFF10B981),
                      title: 'מסמך הזהות התקבל',
                      subtitle: 'תעודת הזהות / הדרכון שלך הועלו בהצלחה.',
                      done: true,
                    ),
                    const _StepDivider(),
                    _step(
                      icon: Icons.manage_search_rounded,
                      color: const Color(0xFF6366F1),
                      title: 'אימות ידני ע"י מנהל',
                      subtitle: 'צוות AnySkill יאמת את הפרטים שלך — בדרך כלל תוך 24 שעות.',
                      done: false,
                    ),
                    const _StepDivider(),
                    _step(
                      icon: Icons.mark_email_read_rounded,
                      color: const Color(0xFFF59E0B),
                      title: 'אימייל אישור',
                      subtitle: 'תקבל/י אימייל ותוכל/י להיכנס לפרופיל המקצועי שלך.',
                      done: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Auto-redirect notice
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: Color(0xFF0EA5E9)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'הדף יעבור אוטומטית לאחר האישור — אין צורך לרענן',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12, color: Colors.blueGrey[700]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Logout button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => performSignOut(context),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text(
                    'התנתק/י בינתיים',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(
                        color: Color(0xFF6366F1), width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool done,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: TextDirection.rtl,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: done
                    ? color.withValues(alpha: 0.15)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: done ? color : Colors.grey.shade400, size: 20),
            ),
            if (done)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                      color: Color(0xFF10B981), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 10),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: done
                          ? const Color(0xFF1F1F33)
                          : Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(subtitle,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[500],
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepDivider extends StatelessWidget {
  const _StepDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade200)),
        ],
      ),
    );
  }
}
