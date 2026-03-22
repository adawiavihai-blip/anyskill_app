import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/permission_service.dart';
import 'home_screen.dart';

class PermissionRequestScreen extends StatefulWidget {
  const PermissionRequestScreen({super.key});

  @override
  State<PermissionRequestScreen> createState() =>
      _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Request both permissions, save status, navigate ────────────────────────
  Future<void> _allowAll() async {
    setState(() => _loading = true);

    // Location
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        await PermissionService.saveLocationStatus(
          (result == LocationPermission.whileInUse ||
                  result == LocationPermission.always)
              ? PermissionService.granted
              : PermissionService.denied,
        );
      } else if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        await PermissionService.saveLocationStatus(PermissionService.granted);
      } else {
        await PermissionService.saveLocationStatus(PermissionService.denied);
      }
    } catch (e) {
      debugPrint('PermissionRequestScreen: location error: $e');
    }

    // Notifications
    try {
      final settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await PermissionService.saveNotificationStatus(
        settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional
            ? PermissionService.granted
            : PermissionService.denied,
      );
    } catch (e) {
      debugPrint('PermissionRequestScreen: notification error: $e');
    }

    await PermissionService.markPermissionsSeen();
    _navigate();
  }

  Future<void> _skipAll() async {
    await PermissionService.markPermissionsSeen();
    _navigate();
  }

  void _navigate() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                // Header icon
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.shield_rounded,
                        color: Colors.white, size: 42),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'כמה הרשאות לפני שמתחילים',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'AnySkill צריכה הרשאות אלו כדי לתת לך את החוויה הטובה ביותר.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 44),
                // Permission cards
                _PermCard(
                  icon: Icons.location_on_rounded,
                  color: const Color(0xFF34D399),
                  title: 'מיקום',
                  subtitle:
                      'הצגת ספקים קרובים אליך ומיון תוצאות לפי מרחק.',
                ),
                const SizedBox(height: 16),
                _PermCard(
                  icon: Icons.notifications_rounded,
                  color: const Color(0xFFFBBF24),
                  title: 'התראות',
                  subtitle:
                      'קבלת עדכונים על הזמנות, הודעות חדשות ומבצעים מיוחדים.',
                ),
                const Spacer(),
                // Primary CTA
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6366F1),
                    ),
                  )
                else ...[
                  _GradBtn(
                    label: 'אפשר הכל',
                    onTap: _allowAll,
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _skipAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'לא עכשיו',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Permission card widget ────────────────────────────────────────────────────
class _PermCard extends StatelessWidget {
  const _PermCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gradient button ───────────────────────────────────────────────────────────
class _GradBtn extends StatelessWidget {
  const _GradBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.42),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
