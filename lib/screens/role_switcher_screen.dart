import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_roles.dart';
import '../utils/safe_image_provider.dart';
import 'home_screen.dart';
import 'support/support_dashboard_screen.dart';

/// Phase 1 — role switcher.
///
/// Shown after sign-in when the user holds more than one role, OR reached
/// manually from the profile menu ("החלף תפקיד"). On selection it writes
/// `users/{uid}.activeRole` and pops — the caller (AuthWrapper /
/// OnboardingGate) re-renders and routes to the matching home.
class RoleSwitcherScreen extends StatefulWidget {
  /// When shown at first-login, pops back to the stream builder. When opened
  /// manually, pops back to where we came from. Either way we just need to
  /// update `activeRole` — the routing layer does the rest.
  final bool allowBack;

  const RoleSwitcherScreen({super.key, this.allowBack = true});

  @override
  State<RoleSwitcherScreen> createState() => _RoleSwitcherScreenState();
}

class _RoleSwitcherScreenState extends State<RoleSwitcherScreen> {
  bool _saving = false;

  Future<void> _select(String role, UserRoles current) async {
    if (_saving) return;
    if (!current.has(role)) return;
    if (role == current.activeRole) {
      _exitTo(role);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'activeRole': role});
      if (!mounted) return;
      _exitTo(role);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בהחלפת תפקיד: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// After the role is persisted, leave the switcher.
  ///
  /// When opened manually from the profile menu (`allowBack=true`) we just
  /// pop back — the screen that pushed the switcher will see the write
  /// propagate via its own stream listener.
  ///
  /// When shown as the initial post-login gate (`allowBack=false`) we have
  /// NO route to pop to, and the OnboardingGate's FutureBuilder won't
  /// re-fire on its own → we'd be stuck on the switcher. In that case we
  /// pushReplacement straight to the home for the picked role.
  void _exitTo(String role) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (widget.allowBack && nav.canPop()) {
      nav.pop(role);
      return;
    }
    final next = role == UserRoles.supportAgent
        ? const SupportDashboardScreen()
        : const HomeScreen();
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => next),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: widget.allowBack,
        title: const Text(
          'בחר תפקיד',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data() ?? {};
          final roles = UserRoles.fromUserDoc(data);
          final user = FirebaseAuth.instance.currentUser;

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Hero avatar + email ─────────────────────────────
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: const Color(0xFFE0E7FF),
                        backgroundImage:
                            safeImageProvider(data['profileImage'] as String?),
                        child: safeImageProvider(
                                    data['profileImage'] as String?) ==
                                null
                            ? Text(
                                (data['name'] as String? ??
                                        user?.email ??
                                        '?')
                                    .characters
                                    .first
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF6366F1),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        (data['name'] as String?) ?? user?.email ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      if (user?.email != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          user!.email!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      const Text(
                        'עם איזה כובע להמשיך הפעם?',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Role cards ──────────────────────────────────────
                      _RoleCard(
                        role: UserRoles.admin,
                        title: 'מנהל/ת המערכת',
                        subtitle: 'ניהול, פיננסים, הגדרות',
                        icon: Icons.admin_panel_settings_rounded,
                        accent: const Color(0xFFEF4444),
                        badge: null,
                        enabled: roles.has(UserRoles.admin),
                        active: roles.activeRole == UserRoles.admin,
                        saving: _saving,
                        onTap: () => _select(UserRoles.admin, roles),
                      ),
                      const SizedBox(height: 12),
                      _RoleCard(
                        role: UserRoles.supportAgent,
                        title: 'סוכן/ת תמיכה',
                        subtitle: 'עבודה בצ\'אט התמיכה, פניות לקוחות',
                        icon: Icons.support_agent_rounded,
                        accent: const Color(0xFF8B5CF6),
                        badge: null,
                        enabled: roles.has(UserRoles.supportAgent),
                        active:
                            roles.activeRole == UserRoles.supportAgent,
                        saving: _saving,
                        onTap: () =>
                            _select(UserRoles.supportAgent, roles),
                      ),
                      const SizedBox(height: 12),
                      _RoleCard(
                        role: UserRoles.provider,
                        title: 'נותן/ת שירות',
                        subtitle: 'הצעות מחיר, יומן עבודה, תשלומים',
                        icon: Icons.handyman_rounded,
                        accent: const Color(0xFF10B981),
                        badge: null,
                        enabled: roles.has(UserRoles.provider),
                        active: roles.activeRole == UserRoles.provider,
                        saving: _saving,
                        onTap: () => _select(UserRoles.provider, roles),
                      ),
                      const SizedBox(height: 12),
                      _RoleCard(
                        role: UserRoles.customer,
                        title: 'לקוח/ה',
                        subtitle: 'חיפוש שירותים, הזמנות, צ\'אטים',
                        icon: Icons.person_rounded,
                        accent: const Color(0xFF6366F1),
                        badge: null,
                        enabled: roles.has(UserRoles.customer),
                        active: roles.activeRole == UserRoles.customer,
                        saving: _saving,
                        onTap: () => _select(UserRoles.customer, roles),
                      ),

                      const SizedBox(height: 20),
                      const Text(
                        'אפשר להחליף תפקיד בכל זמן מתפריט הפרופיל.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String role;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String? badge;
  final bool enabled;
  final bool active;
  final bool saving;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.badge,
    required this.enabled,
    required this.active,
    required this.saving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? Colors.white : const Color(0xFFF3F4F6);
    final borderColor = active
        ? accent
        : (enabled ? const Color(0xFFE5E7EB) : const Color(0xFFE5E7EB));
    final titleColor =
        enabled ? const Color(0xFF1A1A2E) : const Color(0xFF9CA3AF);
    final subColor =
        enabled ? const Color(0xFF6B7280) : const Color(0xFFBFC5CE);

    return Opacity(
      opacity: enabled ? 1 : 0.65,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: (!enabled || saving) ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: active ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: enabled ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                              ),
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'פעיל',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (!enabled) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'לא פעיל',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled && !active)
                  const Icon(Icons.chevron_left_rounded,
                      color: Color(0xFF9CA3AF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
