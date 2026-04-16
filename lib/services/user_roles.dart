/// Phase 1 — Multi-role RBAC helper.
///
/// Single source of truth for deciding what roles a user holds and which
/// one is currently active. Reads the NEW schema first:
///   users/{uid}.roles: ['user', 'support_agent', ...]
///   users/{uid}.activeRole: 'support_agent'
///
/// Falls back to the LEGACY schema during the migration window so any
/// user doc that hasn't been migrated yet keeps working:
///   users/{uid}.role: 'admin' | 'support_agent' | 'user'
///   users/{uid}.isAdmin: true | false
///   users/{uid}.isProvider: true | false
///   users/{uid}.isCustomer: true | false
///
/// Never throws — a doc with no role fields resolves to ['user'].
class UserRoles {
  static const String admin = 'admin';
  static const String supportAgent = 'support_agent';
  static const String provider = 'provider';
  static const String customer = 'customer';
  static const String user = 'user'; // legacy default

  /// All known role ids — used by the role-switcher UI.
  static const List<String> all = [admin, supportAgent, provider, customer];

  final Set<String> roles;
  final String activeRole;

  const UserRoles._(this.roles, this.activeRole);

  /// Build from a users/{uid} document map. Safe to call on empty maps.
  factory UserRoles.fromUserDoc(Map<String, dynamic>? data) {
    data ??= const {};
    final resolved = <String>{};

    // ── NEW schema ───────────────────────────────────────────────────────
    final rawRoles = data['roles'];
    if (rawRoles is List) {
      for (final r in rawRoles) {
        if (r is String && r.isNotEmpty) resolved.add(r);
      }
    }

    // ── LEGACY fallback ─────────────────────────────────────────────────
    // Only consult legacy fields when the new array is absent/empty, so a
    // migrated user whose legacy fields are stale doesn't get extra roles.
    if (resolved.isEmpty) {
      final legacyRole = data['role'];
      if (legacyRole is String && legacyRole.isNotEmpty) {
        resolved.add(legacyRole);
      }
      if (data['isAdmin'] == true) resolved.add(admin);
      if (data['isProvider'] == true) resolved.add(provider);
      if (data['isCustomer'] == true) resolved.add(customer);
    }

    // Legacy 'user' string = customer.
    if (resolved.remove(user)) resolved.add(customer);

    // Last-resort baseline so the helper never returns an empty set.
    // Note: we deliberately do NOT auto-add 'customer' on top of an
    // existing role — that would make every single-role user (admin,
    // agent, provider) look multi-role and incorrectly trigger the role
    // switcher. A real admin/agent/provider stays single-role until an
    // admin explicitly grants them an additional role via the admin tab.
    if (resolved.isEmpty) resolved.add(customer);

    // ── Active role ─────────────────────────────────────────────────────
    String active = (data['activeRole'] as String?) ?? '';
    if (!resolved.contains(active)) {
      // Pick a sensible default in priority order.
      if (resolved.contains(admin)) {
        active = admin;
      } else if (resolved.contains(supportAgent)) {
        active = supportAgent;
      } else if (resolved.contains(provider)) {
        active = provider;
      } else {
        active = customer;
      }
    }

    return UserRoles._(resolved, active);
  }

  bool has(String role) => roles.contains(role);
  bool get isAdmin => roles.contains(admin);
  bool get isSupportAgent => roles.contains(supportAgent);
  bool get isProvider => roles.contains(provider);
  bool get isCustomer => roles.contains(customer);

  /// True iff the user holds more than one role — the role switcher UI
  /// should be shown.
  bool get hasMultiple => roles.length > 1;

  /// Roles ordered for UI display (admin first, then staff, then service,
  /// then customer).
  List<String> get ordered {
    const priority = [admin, supportAgent, provider, customer];
    final out = <String>[];
    for (final p in priority) {
      if (roles.contains(p)) out.add(p);
    }
    return out;
  }

  @override
  String toString() =>
      'UserRoles(roles: $roles, active: $activeRole)';
}
