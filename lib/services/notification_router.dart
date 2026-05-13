// Smart Notification Router (v15.x, 2026-04-18).
//
// Central routing table for tapping a notification doc from the bell-icon
// inbox screen OR from an FCM push payload. Each notification type maps to
// a specific deep-link destination — NOT just a tab index.
//
// Design:
//   - One entry point: [NotificationRouter.route(context, data)].
//   - Returns true  → router consumed the tap (it pushed or popped).
//   - Returns false → caller should fall back to local handling
//                     (e.g. screen-state modals like broadcast claim sheet,
//                      help-request accept sheet, CSAT modal) OR do nothing.
//
// The router's job is Navigator.push for types that have a clean deep-link.
// Types that need a screen-local modal (because the modal depends on the
// parent screen's state or services) return false and stay with the caller.
//
// Notification doc shape (see functions/index.js callsites):
//   { userId, title, body, type, isRead, createdAt,
//     data: { ...type-specific ids }  -- nested
//     chatRoomId?/roomId?/ticketId?/jobId?/taskId? -- some CFs put ids at top level
//     relatedUserId?/category?/broadcastId?  -- legacy CFs
//   }
//
// The helper [_extractField] reads BOTH nested `data.xxx` and top-level,
// so the router works across legacy + new payload formats.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../features/any_tasks/screens/task_tracking_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/community/completion_celebration_screen.dart';
import '../screens/community/confirm_completion_screen.dart';
import '../screens/community/feature_flag.dart';
import '../screens/community/request_detail_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/my_bookings_screen.dart';
import '../screens/provider_ai_insights_screen.dart';
import '../screens/public_profile_screen.dart';
import '../screens/support_center_screen.dart';

class NotificationRouter {
  /// Entry point. Pops the current screen (the notifications inbox)
  /// before pushing the target so the user doesn't end up with a stack
  /// like [Home → Inbox → Chat] — they land on [Home → Chat].
  ///
  /// Returns:
  ///   - `true`  → we routed (either pushed or popped).
  ///   - `false` → caller should handle it locally (e.g. broadcast claim
  ///               sheet, volunteer accept sheet, CSAT modal).
  static Future<bool> route(
    BuildContext context,
    Map<String, dynamic> raw,
  ) async {
    final type = (raw['type'] as String? ?? 'general').trim();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Types with screen-local modals — caller handles.
    const localModalTypes = {
      'help_request',
      'broadcast_urgent',
      'csat_survey',
    };
    if (localModalTypes.contains(type)) return false;

    // ── CHAT ────────────────────────────────────────────────────────────
    if (type == 'chat') {
      final senderId = _extractField(raw, ['senderId', 'relatedUserId']);
      final roomId = _extractField(raw, ['roomId', 'chatRoomId']);
      // Prefer explicit senderId. Else derive from roomId (format: uid1_uid2).
      String otherId = (senderId ?? '').toString();
      if (otherId.isEmpty && roomId != null && roomId.toString().isNotEmpty) {
        otherId = _otherUidFromRoomId(roomId.toString(), uid);
      }
      if (otherId.isNotEmpty) {
        final receiverName = (raw['title'] as String? ?? '').trim();
        await _replaceWith(
          context,
          ChatScreen(receiverId: otherId, receiverName: receiverName),
        );
        return true;
      }
      return false;
    }

    // ── SUPPORT TICKET ──────────────────────────────────────────────────
    if (type == 'support_ticket') {
      final ticketId = _extractField(raw, ['ticketId']);
      if (ticketId != null && ticketId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          TicketChatScreen(
            ticketId: ticketId.toString(),
            category: _extractField(raw, ['category'])?.toString() ?? 'other',
            isAdmin: false,
          ),
        );
        return true;
      }
      // No ticketId — route to support hub instead.
      await _replaceWith(context, const SupportCenterScreen());
      return true;
    }

    // ── BOOKINGS / JOBS ─────────────────────────────────────────────────
    if (type == 'job_status' ||
        type == 'new_booking' ||
        type == 'booking_confirmed' ||
        type == 'booking' ||
        type == 'job_accepted' ||
        type == 'quote_received' ||
        type == 'payment_release') {
      // MyBookingsScreen is the Orders tab. Internally it filters by uid +
      // role and opens to the latest active booking — that's good enough.
      await _replaceWith(context, const MyBookingsScreen());
      return true;
    }

    // ── ANYTASK (all lifecycle events) ──────────────────────────────────
    if (type.startsWith('anytask_')) {
      final taskId = _extractField(raw, ['taskId']);
      if (taskId != null && taskId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          TaskTrackingScreen(taskId: taskId.toString()),
        );
        return true;
      }
      // Without taskId we can't deep-link — just pop back to Home.
      await _popToFirst(context);
      return true;
    }

    // ── COMMUNITY HUB new request (Phase F, v15.x — mockup 16) ──────────
    // Volunteer received a notification about a new request. v2 viewers
    // deep-link straight to [RequestDetailScreen] (mockup 02). v1 viewers
    // fall through to home tab so the legacy hub picks them up.
    if (type == 'community_request') {
      final requestId = _extractField(raw, ['requestId']);
      if (isCommunityV2EnabledFor(uid) &&
          requestId != null &&
          requestId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          RequestDetailScreen(requestId: requestId.toString()),
        );
        return true;
      }
      // v1: just pop to home (legacy banner takes them to legacy hub).
      await _popToFirst(context);
      return true;
    }

    // ── COMMUNITY HUB pending confirmation (Phase D-2, v15.x) ───────────
    // Volunteer marked the task done — requester needs to confirm.
    // For v2-whitelisted requesters we deep-link to the new
    // [ConfirmCompletionScreen] (mockup 05) which captures the rating
    // and writes it to `community_requests/{id}.rating`. v1 requesters
    // fall through to the legacy flow (chat with the volunteer).
    if (type == 'community_pending_confirmation') {
      final requestId = _extractField(raw, ['requestId']);
      if (isCommunityV2EnabledFor(uid) &&
          requestId != null &&
          requestId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          ConfirmCompletionScreen(requestId: requestId.toString()),
        );
        return true;
      }
      // v1 fallback: open chat with the volunteer.
      final otherId = _extractField(raw, ['relatedUserId']);
      if (otherId != null && otherId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          ChatScreen(
            receiverId: otherId.toString(),
            receiverName: (raw['title'] as String? ?? '').trim(),
          ),
        );
        return true;
      }
      return false;
    }

    // ── COMMUNITY HUB completion (Phase C, v15.x) ───────────────────────
    // For v2-whitelisted volunteers we deep-link to the new
    // [CompletionCelebrationScreen] (mockup 06). For everyone else we
    // fall through to the legacy chat-with-requester behavior so the
    // experience is unchanged until the feature flag is lifted.
    if (type == 'community_completed') {
      final requestId = _extractField(raw, ['requestId']);
      if (isCommunityV2EnabledFor(uid) &&
          requestId != null &&
          requestId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          CompletionCelebrationScreen(requestId: requestId.toString()),
        );
        return true;
      }
      // v1 fallback: open chat with the requester (matches legacy
      // volunteer_completed routing below).
      final otherId = _extractField(raw, ['relatedUserId', 'senderId']);
      if (otherId != null && otherId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          ChatScreen(
            receiverId: otherId.toString(),
            receiverName: (raw['title'] as String? ?? '').trim(),
          ),
        );
        return true;
      }
      return false;
    }

    // ── VOLUNTEER follow-ups (chat-linked) ──────────────────────────────
    if (type == 'volunteer_accepted' ||
        type == 'volunteer_completed' ||
        type == 'broadcast_claimed') {
      final otherId = _extractField(raw, ['relatedUserId', 'senderId']);
      if (otherId != null && otherId.toString().isNotEmpty) {
        await _replaceWith(
          context,
          ChatScreen(
            receiverId: otherId.toString(),
            receiverName: (raw['title'] as String? ?? '').trim(),
          ),
        );
        return true;
      }
      return false;
    }

    // ── PAYMENT-RELATED → finance screen ────────────────────────────────
    if (type == 'payment_received' ||
        type == 'wallet_credit' ||
        type == 'admin_credit_grant' ||
        type == 'withdrawal_status') {
      await _replaceWith(context, const FinanceScreen());
      return true;
    }

    // ── AI / PRO notifications ──────────────────────────────────────────
    // pro_revoked added in Phase 2 — same destination as pro_granted so
    // the provider can see exactly which criterion failed in the dashboard.
    if (type == 'ai_insight' ||
        type == 'ai_suggestion' ||
        type == 'pro_granted' ||
        type == 'pro_revoked') {
      await _replaceWith(context, const ProviderAiInsightsScreen());
      return true;
    }

    // ── REVIEW RECEIVED → open reviewee's public profile ────────────────
    if (type == 'review_received' || type == 'review') {
      final targetUid =
          _extractField(raw, ['relatedUserId', 'revieweeId']) ?? uid;
      if (targetUid.toString().isNotEmpty) {
        await _replaceWith(
          context,
          PublicProfileScreen(userId: targetUid.toString()),
        );
        return true;
      }
      return false;
    }

    // ── FLASH AUCTION (CLAUDE.md §57) ───────────────────────────────────
    // Both the provider dispatch ('flash_auction_dispatch') and the customer
    // offer-arrival ('flash_auction_offer') intentionally route to Home —
    // they're rendered by surfaces that ALREADY live on the Home tab:
    //   • Provider side → _FlashAuctionsStrip at the top of the Opportunities
    //     tab shows the live card with the ETA input.
    //   • Customer side → the cold-start case is rare (the customer is
    //     usually still inside FlashAuctionSearchingScreen which auto-
    //     navigates to the offers screen on first offer). For background
    //     taps, the home fallback is acceptable because the auction is
    //     short-lived (≤ 120s) and the customer will see "no active
    //     auction" if it already expired.
    // Documented as the intentional behavior — do NOT add a screen push
    // here without coordinating with the strip / searching screen logic.
    const flashAuctionTypes = {
      'flash_auction_dispatch',
      'flash_auction_offer',
    };

    // ── PROVIDER APPROVED / REQUEST DECLINED / RE-ENGAGEMENT / GENERIC ──
    // These are informational-only — user saw the banner text, no specific
    // deep-link destination. Just pop back to Home so they can continue.
    const homeFallbackTypes = {
      'provider_approved',
      'request_declined',
      'seasonal',
      'geo_nearby',
      'rebook_reminder',
      'inactivity_reminder',
      'reengagement',
      'reengagement_abandoned',
      'market_alert',
      'admin_payment_alert',
      'demo_contact',
      'general',
    };
    if (flashAuctionTypes.contains(type) || homeFallbackTypes.contains(type)) {
      await _popToFirst(context);
      return true;
    }

    // Unknown type — let the caller decide.
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Internal helpers
  // ═══════════════════════════════════════════════════════════════════════

  /// Reads a field from EITHER the top level OR the nested `data` map.
  /// Returns the first non-empty value for any key in [keys], else null.
  static dynamic _extractField(Map<String, dynamic> raw, List<String> keys) {
    for (final k in keys) {
      final top = raw[k];
      if (top != null && top.toString().isNotEmpty) return top;
    }
    final nested = raw['data'];
    if (nested is Map) {
      for (final k in keys) {
        final v = nested[k];
        if (v != null && v.toString().isNotEmpty) return v;
      }
    }
    return null;
  }

  /// Extracts the "other" uid from a `chats/{roomId}` doc id of the form
  /// `uid1_uid2` (sorted join). Returns empty if no second participant.
  static String _otherUidFromRoomId(String roomId, String selfUid) {
    final parts = roomId.split('_');
    if (parts.isEmpty) return '';
    return parts.firstWhere(
      (p) => p != selfUid && p.isNotEmpty,
      orElse: () => parts.first,
    );
  }

  /// Pops the notifications inbox (or wherever the caller lives) and
  /// pushes the target on top of whatever is below. Net effect: inbox is
  /// replaced by the deep-link destination, matching FCM tap behavior.
  static Future<void> _replaceWith(
    BuildContext context,
    Widget target,
  ) async {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
    // Use post-frame so the pop completes before the push (prevents the
    // "setState during build" race when coming from a notification onTap).
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
  }

  /// Pops back to the root route (Home). Used for informational
  /// notifications that don't deep-link anywhere specific.
  static Future<void> _popToFirst(BuildContext context) async {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}
