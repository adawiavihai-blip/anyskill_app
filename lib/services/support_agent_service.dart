import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Centralized service for the Support Workspace.
///
/// All ticket assignment, SLA computation, role checks, and agent action
/// dispatch happen here. UI widgets call these methods rather than touching
/// Firestore directly — keeps the security model and audit trail consistent.
class SupportAgentService {
  SupportAgentService._();

  static final _db = FirebaseFirestore.instance;
  static final _fn = FirebaseFunctions.instance;

  // ── Role constants ─────────────────────────────────────────────────────
  static const String roleAdmin = 'admin';
  static const String roleSupportAgent = 'support_agent';
  static const String roleUser = 'user';

  // ── SLA thresholds (in minutes) ────────────────────────────────────────
  static const int slaWarningMinutes = 5; // yellow
  static const int slaBreachedMinutes = 10; // red flashing

  // ── Refund cap for support_agent (admin has no cap via processRefund) ──
  static const double supportAgentRefundCapNis = 1000.0;

  // ───────────────────────────────────────────────────────────────────────
  // ROLE DETECTION
  // ───────────────────────────────────────────────────────────────────────

  /// Resolves the role of the currently signed-in user.
  /// Returns one of: 'admin', 'support_agent', 'user', or null if not signed in.
  ///
  /// Reads `users/{uid}.role` first, falling back to `isAdmin == true` for
  /// backward compatibility with users that pre-date the role field.
  static Future<String?> currentRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (!snap.exists) return null;
      return _resolveRole(snap.data() ?? {});
    } catch (e) {
      debugPrint('[SupportAgentService] currentRole error: $e');
      return null;
    }
  }

  /// Stream the current user's role for reactive UI updates.
  static Stream<String?> watchCurrentRole() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? _resolveRole(snap.data() ?? {}) : null);
  }

  /// Pure helper — extracts role from a user document map.
  /// Use this when you already have the user data (e.g., from a stream).
  static String resolveRole(Map<String, dynamic> userData) =>
      _resolveRole(userData);

  static String _resolveRole(Map<String, dynamic> data) {
    // Explicit role field takes precedence (new model)
    final role = data['role'] as String?;
    if (role != null && role.isNotEmpty) return role;
    // Fallback for legacy users with only isAdmin
    if (data['isAdmin'] == true) return roleAdmin;
    return roleUser;
  }

  static bool isAdmin(Map<String, dynamic> userData) =>
      _resolveRole(userData) == roleAdmin;

  static bool isSupportAgent(Map<String, dynamic> userData) =>
      _resolveRole(userData) == roleSupportAgent;

  static bool isStaff(Map<String, dynamic> userData) {
    final r = _resolveRole(userData);
    return r == roleAdmin || r == roleSupportAgent;
  }

  // ───────────────────────────────────────────────────────────────────────
  // ROLE MANAGEMENT (admin-only — calls Cloud Function)
  // ───────────────────────────────────────────────────────────────────────

  /// Admin grants/revokes a role on another user via the setUserRole CF.
  /// Returns the result map from the CF on success.
  ///
  /// Throws on failure (FirebaseFunctionsException). Caller should wrap in
  /// try/catch and surface the error to the UI.
  static Future<Map<String, dynamic>> setUserRole({
    required String targetUserId,
    required String newRole,
  }) async {
    final result = await _fn.httpsCallable('setUserRole').call({
      'targetUserId': targetUserId,
      'newRole': newRole,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ───────────────────────────────────────────────────────────────────────
  // TICKET QUEUE — streams + assignment
  // ───────────────────────────────────────────────────────────────────────

  /// Stream all open + in_progress tickets for the queue view.
  /// Sorted by createdAt DESC so newest tickets surface first; SLA timer
  /// in the UI re-prioritizes visually based on age.
  static Stream<List<Map<String, dynamic>>> streamOpenQueue({
    int limit = 100,
    String? filterStatus,
    String? filterPriority,
    String? assignedToFilter, // 'me' | 'unassigned' | uid | null
  }) {
    Query<Map<String, dynamic>> q = _db.collection('support_tickets');

    if (filterStatus != null && filterStatus.isNotEmpty) {
      q = q.where('status', isEqualTo: filterStatus);
    } else {
      // Default: open or in_progress (anything not yet resolved/closed)
      q = q.where('status', whereIn: ['open', 'in_progress']);
    }

    if (filterPriority != null && filterPriority.isNotEmpty) {
      q = q.where('priority', isEqualTo: filterPriority);
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (assignedToFilter == 'me' && myUid != null) {
      q = q.where('assignedTo', isEqualTo: myUid);
    } else if (assignedToFilter == 'unassigned') {
      q = q.where('assignedTo', isNull: true);
    } else if (assignedToFilter != null &&
        assignedToFilter != 'me' &&
        assignedToFilter != 'unassigned') {
      q = q.where('assignedTo', isEqualTo: assignedToFilter);
    }

    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              m['ticketId'] = d.id;
              return m;
            }).toList());
  }

  /// Stream a single ticket document for the workspace center pane.
  static Stream<Map<String, dynamic>?> watchTicket(String ticketId) {
    return _db
        .collection('support_tickets')
        .doc(ticketId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      final m = snap.data() ?? {};
      m['ticketId'] = snap.id;
      return m;
    });
  }

  /// Claim a ticket — assign it to the current agent.
  /// Sets assignedTo, assignedToName, status (→ in_progress), and writes
  /// an audit log entry.
  static Future<void> claimTicket({
    required String ticketId,
    required String agentName,
  }) async {
    final agentUid = FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null) throw Exception('Not signed in');

    await _db.collection('support_tickets').doc(ticketId).update({
      'assignedTo': agentUid,
      'assignedToName': agentName,
      'status': 'in_progress',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Release a ticket back to the queue (un-assign).
  static Future<void> releaseTicket(String ticketId) async {
    await _db.collection('support_tickets').doc(ticketId).update({
      'assignedTo': null,
      'assignedToName': null,
      'status': 'open',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Change ticket priority. Allowed values: low, normal, high, urgent.
  static Future<void> setPriority({
    required String ticketId,
    required String priority,
  }) async {
    const allowed = {'low', 'normal', 'high', 'urgent'};
    if (!allowed.contains(priority)) {
      throw ArgumentError('Invalid priority: $priority');
    }
    await _db.collection('support_tickets').doc(ticketId).update({
      'priority': priority,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Close a ticket. Sets status, closedAt, closedBy, and triggers a
  /// notification to the customer prompting them to fill the CSAT survey.
  static Future<void> closeTicket({
    required String ticketId,
    required String customerUserId,
  }) async {
    final agentUid = FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null) throw Exception('Not signed in');

    final batch = _db.batch();

    // Update ticket
    final ticketRef = _db.collection('support_tickets').doc(ticketId);
    batch.update(ticketRef, {
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'closedBy': agentUid,
      'csatRequested': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Notify the customer to fill the survey
    final notifRef = _db.collection('notifications').doc();
    batch.set(notifRef, {
      'userId': customerUserId,
      'type': 'csat_survey',
      'title': '⭐ איך הייתה התמיכה?',
      'body': 'עזור לנו להשתפר — דרג את השירות שקיבלת',
      'isRead': false,
      'data': {'ticketId': ticketId},
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Reopen a closed ticket (admin or original agent only).
  static Future<void> reopenTicket(String ticketId) async {
    await _db.collection('support_tickets').doc(ticketId).update({
      'status': 'in_progress',
      'closedAt': FieldValue.delete(),
      'closedBy': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // MESSAGES — public + internal notes
  // ───────────────────────────────────────────────────────────────────────

  /// Send a message in a ticket. If [isInternal] is true, the message is
  /// hidden from the customer (visible only to staff via firestore rules).
  static Future<void> sendMessage({
    required String ticketId,
    required String message,
    required String agentName,
    bool isInternal = false,
  }) async {
    final agentUid = FirebaseAuth.instance.currentUser?.uid;
    if (agentUid == null) throw Exception('Not signed in');
    if (message.trim().isEmpty) return;

    final batch = _db.batch();

    final msgRef = _db
        .collection('support_tickets')
        .doc(ticketId)
        .collection('messages')
        .doc();
    batch.set(msgRef, {
      'senderId': agentUid,
      'senderName': isInternal ? '[פנימי] $agentName' : agentName,
      'isAdmin': true, // staff messages always render as admin-side bubble
      'isInternal': isInternal,
      'message': message.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update ticket metadata
    final ticketRef = _db.collection('support_tickets').doc(ticketId);
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      if (!isInternal) 'lastAgentMessageAt': FieldValue.serverTimestamp(),
    };
    batch.update(ticketRef, updates);

    await batch.commit();
  }

  /// Stream messages for a ticket. Internal notes are included if [includeInternal]
  /// is true (the support workspace passes true; the customer chat passes false).
  static Stream<List<Map<String, dynamic>>> streamMessages(
    String ticketId, {
    bool includeInternal = true,
    int limit = 200,
  }) {
    return _db
        .collection('support_tickets')
        .doc(ticketId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final m = d.data();
              m['messageId'] = d.id;
              return m;
            })
            .where((m) => includeInternal || m['isInternal'] != true)
            .toList());
  }

  // ───────────────────────────────────────────────────────────────────────
  // SLA helpers
  // ───────────────────────────────────────────────────────────────────────

  /// Computes the SLA state of a ticket based on its age.
  /// 'on_track' = green, 'warning' = yellow, 'breached' = red.
  static String slaStateFor(Map<String, dynamic> ticket) {
    final createdAt = ticket['createdAt'] as Timestamp?;
    if (createdAt == null) return 'on_track';
    if (ticket['status'] == 'resolved' || ticket['status'] == 'closed') {
      return 'on_track';
    }
    // If an agent has already replied, the SLA pressure is off.
    if (ticket['lastAgentMessageAt'] != null) return 'on_track';

    final ageMin = DateTime.now().difference(createdAt.toDate()).inMinutes;
    if (ageMin >= slaBreachedMinutes) return 'breached';
    if (ageMin >= slaWarningMinutes) return 'warning';
    return 'on_track';
  }

  /// Returns the age of a ticket as a human-readable Hebrew string.
  static String formatTicketAge(Map<String, dynamic> ticket) {
    final createdAt = ticket['createdAt'] as Timestamp?;
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt.toDate());
    if (diff.inMinutes < 1) return 'הרגע';
    if (diff.inMinutes < 60) return '${diff.inMinutes} דק\'';
    if (diff.inHours < 24) return '${diff.inHours} שע\'';
    return '${diff.inDays} ימים';
  }

  // ───────────────────────────────────────────────────────────────────────
  // AGENT ACTIONS — calls supportAgentAction CF
  // ───────────────────────────────────────────────────────────────────────

  /// Verify a customer's identity (sets isVerified = true).
  static Future<void> verifyIdentity({
    required String targetUserId,
    required String reason,
    String? ticketId,
  }) async {
    await _fn.httpsCallable('supportAgentAction').call({
      'action': 'verify_identity',
      'targetUserId': targetUserId,
      'reason': reason,
      'ticketId': ticketId,
    });
  }

  /// Send a password reset email to the customer.
  static Future<void> sendPasswordReset({
    required String targetUserId,
    required String reason,
    String? ticketId,
  }) async {
    await _fn.httpsCallable('supportAgentAction').call({
      'action': 'send_password_reset',
      'targetUserId': targetUserId,
      'reason': reason,
      'ticketId': ticketId,
    });
  }

  /// Flag an account for review.
  static Future<void> flagAccount({
    required String targetUserId,
    required String reason,
    String? ticketId,
  }) async {
    await _fn.httpsCallable('supportAgentAction').call({
      'action': 'flag_account',
      'targetUserId': targetUserId,
      'reason': reason,
      'ticketId': ticketId,
    });
  }

  /// Unflag an account.
  static Future<void> unflagAccount({
    required String targetUserId,
    required String reason,
    String? ticketId,
  }) async {
    await _fn.httpsCallable('supportAgentAction').call({
      'action': 'unflag_account',
      'targetUserId': targetUserId,
      'reason': reason,
      'ticketId': ticketId,
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // CUSTOMER 360 CONTEXT
  // ───────────────────────────────────────────────────────────────────────

  /// Loads the full customer profile + recent activity for the workspace
  /// right pane. Single-shot read; refresh by calling again.
  ///
  /// Returns a map with: profile, recentJobs, recentTransactions, ticketsCount.
  static Future<Map<String, dynamic>> loadCustomer360({
    required String customerUserId,
  }) async {
    final profileSnap =
        await _db.collection('users').doc(customerUserId).get();
    final profile = profileSnap.data() ?? {};

    // Recent jobs (last 10) — both as customer and as expert
    final jobsAsCustomer = await _db
        .collection('jobs')
        .where('customerId', isEqualTo: customerUserId)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    // Recent transactions (last 10)
    final txAsReceiver = await _db
        .collection('transactions')
        .where('userId', isEqualTo: customerUserId)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();

    // Open tickets count for context
    final openTicketsSnap = await _db
        .collection('support_tickets')
        .where('userId', isEqualTo: customerUserId)
        .where('status', whereIn: ['open', 'in_progress'])
        .limit(20)
        .get();

    return {
      'profile': profile,
      'recentJobs': jobsAsCustomer.docs.map((d) {
        final m = d.data();
        m['jobId'] = d.id;
        return m;
      }).toList(),
      'recentTransactions': txAsReceiver.docs.map((d) {
        final m = d.data();
        m['txId'] = d.id;
        return m;
      }).toList(),
      'openTicketsCount': openTicketsSnap.docs.length,
    };
  }

  // ───────────────────────────────────────────────────────────────────────
  // CSAT survey
  // ───────────────────────────────────────────────────────────────────────

  /// Customer submits a CSAT rating for a closed ticket.
  /// Allowed values: 1-5 (stars).
  static Future<void> submitCsatRating({
    required String ticketId,
    required int rating,
    String? comment,
  }) async {
    if (rating < 1 || rating > 5) {
      throw ArgumentError('Rating must be 1-5');
    }
    await _db.collection('support_tickets').doc(ticketId).update({
      'csatRating': rating,
      'csatComment': comment?.trim() ?? '',
      'csatSubmittedAt': FieldValue.serverTimestamp(),
    });
  }
}
