import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show EmailCollectionScreen, rootNavigatorKey;
import '../services/account_deletion_service.dart';
import '../services/audio_service.dart';
import '../services/cached_readers.dart';
import '../services/location_service.dart';
import '../services/permission_service.dart';
import 'finance_screen.dart';
import 'phone_login_screen.dart';

/// Account Settings screen — entry point reachable from the Profile tab,
/// rendered above the Logout button. Hosts user preferences (invoice email,
/// app sounds) and destructive account-level actions (delete account).
///
/// Toggles are intentionally hosted here (NOT on the Profile tab) so the
/// Profile tab stays focused on identity, stats, and reviews.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen>
    with WidgetsBindingObserver {
  // ── Local UI state ─────────────────────────────────────────────────────
  // Optimistic-override pattern matches the legacy implementation in
  // profile_screen.dart (now removed) — keeps the toggle from flickering
  // back to the old value while the Firestore write round-trips.
  bool? _invoiceEmailOverride;
  bool _invoiceEmailSaving = false;
  bool _soundEnabled = AudioService.instance.soundEnabled;

  // GPS location state. `_locationEnabled` mirrors the OS-level location
  // permission — the real source of truth. The app cannot revoke an OS
  // permission, so the toggle re-syncs on mount and on every app resume.
  bool _locationEnabled = false;
  bool _locationChecking = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  // The Firestore user-doc stream feeds the email invoice toggle. Held as
  // a field so re-builds don't tear down the snapshot listener.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_user?.uid ?? '_no_user_')
          .snapshots();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLocationState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user may have changed the location permission in
    // the browser / device settings while the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      _refreshLocationState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'הגדרות חשבון',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            // ── My Account ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                'החשבון שלי',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.2,
                ),
              ),
            ),
            // Wallet — moved here from the bottom navigation bar so the
            // customer's nav stays focused on browse/book/chat.
            _buildWalletEntry(),

            const SizedBox(height: 28),

            // ── Preferences ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                'העדפות',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.2,
                ),
              ),
            ),
            // Email Invoice Preference — depends on live user doc data.
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userStream,
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                return _buildEmailInvoiceToggle(data);
              },
            ),
            const SizedBox(height: 12),
            // Sound Mute — per-device, SharedPreferences-backed.
            _buildSoundMuteToggle(),
            const SizedBox(height: 12),
            // Location (GPS) — mirrors the OS-level location permission.
            _buildLocationToggle(),

            const SizedBox(height: 28),

            // ── Danger Zone ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                'אזור מסוכן',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade100),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.profDeleteAccount,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'פעולה זו אינה הפיכה. כל הנתונים שלך, ההזמנות, הביקורות וההיסטוריה יימחקו לצמיתות.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => _showDeleteAccountDialog(context),
                    icon: const Icon(Icons.delete_forever_rounded,
                        size: 18, color: Colors.red),
                    label: Text(
                      l10n.profDeleteAccount,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: Colors.red, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Wallet Entry ────────────────────────────────────────────────────────
  //
  // The wallet ("ארנק") used to be a dedicated bottom-nav tab for every user.
  // For customers it was moved here so their navigation bar stays focused on
  // browse/book/chat. Tapping pushes [FinanceScreen] as a normal route.
  Widget _buildWalletEntry() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        leading: const Icon(
          Icons.account_balance_wallet_rounded,
          color: Color(0xFF6366F1),
        ),
        title: const Text(
          'ארנק',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'צפייה ביתרה ובהיסטוריית התשלומים',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_left_rounded,
          color: Color(0xFF9CA3AF),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinanceScreen()),
        ),
      ),
    );
  }

  // ── Email Invoice Preference Toggle ─────────────────────────────────────
  //
  // Tracks `users/{uid}.receiveEmailReceipts`. The toggle's displayed value
  // comes from the parent stream (`_userStream`) — so every successful write
  // round-trips through the snapshot listener and updates the UI naturally.
  //
  // Local override: while a write is in flight (or just succeeded but the
  // stream hasn't emitted yet), `_invoiceEmailOverride` keeps the switch
  // showing the new value so the UI doesn't flicker back to the old one.
  // Cleared after 4s as a safety so a stuck write can't hide the truth
  // forever.
  //
  // Resilience to Firebase Web SDK b815/ca9: SDK 12.9.0
  // `WatchChangeAggregator` occasionally throws an INTERNAL ASSERTION FAILED
  // even though the underlying write commits. We detect that string and
  // treat it as a soft success — verify via a direct re-read.
  Widget _buildEmailInvoiceToggle(Map<String, dynamic> data) {
    // Default: true (new accounts receive invoices by default — backwards compatible)
    final remoteValue = data['receiveEmailReceipts'] as bool? ?? true;
    final email = (data['email'] as String? ?? '').trim();
    final hasEmail = email.isNotEmpty;
    // When no email is saved, force the displayed value OFF regardless of the
    // remote value — the CF would silently skip sending anyway (no `email`
    // field to deliver to). This keeps the UI honest about what's actually
    // happening, AND makes a tap-to-ON go through the email-collection flow.
    final displayValue =
        _invoiceEmailOverride ?? (hasEmail ? remoteValue : false);
    final saving = _invoiceEmailSaving;
    final l10n = AppLocalizations.of(context);

    final String subtitleText;
    if (!hasEmail) {
      subtitleText = l10n.profInvoiceEmailNeedsEmail;
    } else if (displayValue) {
      subtitleText = l10n.profInvoiceEmailSubOn;
    } else {
      subtitleText = l10n.profInvoiceEmailSubOff;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        onTap: saving
            ? null
            : () => _toggleInvoiceEmail(!displayValue, hasEmail: hasEmail),
        leading: Icon(
          hasEmail
              ? Icons.receipt_long_rounded
              : Icons.mark_email_unread_outlined,
          color: hasEmail
              ? const Color(0xFF6366F1)
              : const Color(0xFFF59E0B),
        ),
        title: Text(
          l10n.profInvoiceEmailTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitleText,
          style: TextStyle(
            color: hasEmail ? Colors.grey[600] : const Color(0xFFB45309),
            fontSize: 12,
          ),
        ),
        trailing: _OnOffPill(value: displayValue, loading: saving),
      ),
    );
  }

  Future<void> _toggleInvoiceEmail(
    bool target, {
    required bool hasEmail,
  }) async {
    final uid = _user?.uid;
    if (uid == null) return;

    if (target && !hasEmail) {
      final added = await _openEmailCollectionForInvoice();
      if (!mounted) return;
      if (added) {
        await _toggleInvoiceEmail(true, hasEmail: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).profInvoiceEmailSkipped),
            backgroundColor: const Color(0xFFF59E0B),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _invoiceEmailOverride = target;
      _invoiceEmailSaving = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final successMsg = target ? l10n.profInvoiceEmailOn : l10n.profInvoiceEmailOff;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'receiveEmailReceipts': target},
        SetOptions(merge: true),
      );
      CachedReaders.invalidateProvider(uid); // §61
      if (!mounted) return;
      setState(() => _invoiceEmailSaving = false);
      _scheduleInvoiceOverrideClear();
      messenger.showSnackBar(SnackBar(
        content: Text(successMsg),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final isSdkAssertion = raw.contains('INTERNAL ASSERTION FAILED') ||
          raw.contains('Unexpected state') ||
          raw.contains('b815') ||
          raw.contains('ca9');

      if (isSdkAssertion) {
        final committed = await _verifyInvoicePreference(uid, target);
        if (!mounted) return;
        setState(() => _invoiceEmailSaving = false);
        if (committed) {
          _scheduleInvoiceOverrideClear();
          messenger.showSnackBar(SnackBar(
            content: Text(successMsg),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ));
        } else {
          setState(() => _invoiceEmailOverride = null);
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.profSaveError(raw)),
            backgroundColor: const Color(0xFFEF4444),
            action: SnackBarAction(
              label: 'נסה שוב',
              textColor: Colors.white,
              onPressed: () => _toggleInvoiceEmail(target, hasEmail: true),
            ),
          ));
        }
        return;
      }

      setState(() {
        _invoiceEmailOverride = null;
        _invoiceEmailSaving = false;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.profSaveError(raw)),
        backgroundColor: const Color(0xFFEF4444),
        action: SnackBarAction(
          label: 'נסה שוב',
          textColor: Colors.white,
          onPressed: () => _toggleInvoiceEmail(target, hasEmail: true),
        ),
      ));
    }
  }

  /// Pushes [EmailCollectionScreen] as a modal route and returns true iff
  /// the user completed the OTP verification (i.e. `verifyEmailCode` CF wrote
  /// `email` + `emailVerifiedAt` to their user doc).
  Future<bool> _openEmailCollectionForInvoice() async {
    final uid = _user?.uid;
    if (uid == null) return false;

    Map<String, dynamic> existingData;
    try {
      existingData = await CachedReaders.providerProfile(uid);
    } catch (_) {
      existingData = const <String, dynamic>{};
    }
    if (!mounted) return false;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EmailCollectionScreen(
          existingData: existingData,
          onSuccess: () => Navigator.of(context).pop(true),
          onSkip: () => Navigator.of(context).pop(false),
        ),
      ),
    );

    CachedReaders.invalidateProvider(uid);
    return completed == true;
  }

  /// Direct one-shot read of the user doc to confirm whether the toggle
  /// write actually committed (used after a Firestore SDK b815/ca9
  /// assertion). 3-second timeout so a hanging network never freezes the UI.
  Future<bool> _verifyInvoicePreference(String uid, bool expected) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      final actual = (snap.data()?['receiveEmailReceipts'] as bool?) ?? true;
      return actual == expected;
    } catch (_) {
      return false;
    }
  }

  /// Clears `_invoiceEmailOverride` after 4s so a stale optimistic state
  /// can never permanently mask the real Firestore value.
  void _scheduleInvoiceOverrideClear() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _invoiceEmailOverride = null);
    });
  }

  // ── Sound Mute Toggle ─────────────────────────────────────────────────────
  //
  // Per-device mute switch backed by `AudioService.instance.setSoundEnabled`.
  // Persists to SharedPreferences (NOT Firestore).
  //
  // ON  = sounds play (default)
  // OFF = `AudioService.play` returns early before instructing any AudioPlayer.
  //
  // Haptic feedback still fires when sounds are muted so users keep tactile
  // feedback on iOS even with the ringer switch off.
  Widget _buildSoundMuteToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        onTap: () => _toggleSound(!_soundEnabled),
        leading: Icon(
          _soundEnabled
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          color: const Color(0xFF6366F1),
        ),
        title: const Text(
          'צלילי האפליקציה',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _soundEnabled
              ? 'התראות + פעולות יושמעו עם צליל'
              : 'האפליקציה תשתיק את כל הצלילים',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: _OnOffPill(value: _soundEnabled),
      ),
    );
  }

  Future<void> _toggleSound(bool val) async {
    setState(() => _soundEnabled = val);
    try {
      await AudioService.instance.setSoundEnabled(val);
    } catch (_) {
      if (!mounted) return;
      setState(() => _soundEnabled = !val);
      return;
    }
    if (val) {
      unawaited(AudioService.instance.playEvent(AppEvent.onPaymentSuccess));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(val
          ? 'צלילי האפליקציה הופעלו 🔊'
          : 'צלילי האפליקציה הושתקו 🔇'),
      duration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF10B981),
    ));
  }

  // ── Location (GPS) Toggle ───────────────────────────────────────────────
  //
  // Mirrors the OS-level location permission — the real source of truth.
  // The app cannot revoke an OS permission, so:
  //   • OFF + tap → runs the LocationService permission/request flow.
  //   • ON  + tap → explains that disabling is done in device/browser
  //                 settings (an honest, iOS-Settings-style behaviour).
  // The pill stays "synced properly" because `_refreshLocationState` runs
  // on mount and again every time the app is resumed (lifecycle hook).
  Widget _buildLocationToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        onTap: _locationChecking ? null : _toggleLocation,
        leading: Icon(
          _locationEnabled
              ? Icons.location_on_rounded
              : Icons.location_off_rounded,
          color: const Color(0xFF6366F1),
        ),
        title: const Text(
          'מיקום (GPS)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _locationEnabled
              ? 'האפליקציה מציגה ספקים קרובים וממיינת תוצאות לפי מרחק'
              : 'הפעל כדי לראות ספקים קרובים אליך ולמיין לפי מרחק',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: _OnOffPill(
          value: _locationEnabled,
          loading: _locationChecking,
        ),
      ),
    );
  }

  /// Re-reads the OS location permission and updates the pill so it stays
  /// in sync with reality (browser/device settings can change underneath).
  Future<void> _refreshLocationState() async {
    // A cached position means location is working right now — trust it
    // even if the web Permissions API reports a stale "denied".
    if (LocationService.cached != null) {
      if (mounted && !_locationEnabled) {
        setState(() => _locationEnabled = true);
      }
      return;
    }
    try {
      final perm = await Geolocator.checkPermission();
      final granted = perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
      if (!mounted) return;
      if (granted != _locationEnabled) {
        setState(() => _locationEnabled = granted);
      }
    } catch (_) {
      // Leave the current value untouched — never crash settings.
    }
  }

  Future<void> _toggleLocation() async {
    // Already granted — the app can't revoke an OS permission; point the
    // user to the device/browser settings instead.
    if (_locationEnabled) {
      _showLocationDisableInfo();
      return;
    }

    setState(() => _locationChecking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pos = await LocationService.requestAndGet(context);
      if (!mounted) return;
      if (pos != null) {
        await PermissionService.saveLocationStatus(PermissionService.granted);
        if (!mounted) return;
        setState(() {
          _locationEnabled = true;
          _locationChecking = false;
        });
        messenger.showSnackBar(const SnackBar(
          content: Text('מיקום הופעל 📍'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ));
      } else {
        setState(() => _locationChecking = false);
        // The user may have granted at the OS level even though the fix
        // failed — re-check so the pill never lies.
        await _refreshLocationState();
        if (!mounted) return;
        if (!_locationEnabled) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
                'לא ניתן לקבל גישה למיקום. ניתן לאפשר זאת בהגדרות הדפדפן/המכשיר.'),
            backgroundColor: Color(0xFFF59E0B),
            duration: Duration(seconds: 4),
          ));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationChecking = false);
      messenger.showSnackBar(SnackBar(
        content: Text('שגיאה בהפעלת המיקום: $e'),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  /// Explains that turning location OFF is done in the device/browser
  /// settings — the app itself cannot revoke an OS-level permission.
  void _showLocationDisableInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: const [
            Text('כיבוי מיקום',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.location_off_rounded, color: Color(0xFF6366F1)),
          ],
        ),
        content: const Text(
          'כדי לכבות את הגישה למיקום יש לבטל את הרשאת המיקום בהגדרות הדפדפן '
          'או המכשיר. האפליקציה אינה יכולה לבטל את ההרשאה בעצמה.',
          textAlign: TextAlign.right,
          style: TextStyle(height: 1.5, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }

  // ── Account Deletion ────────────────────────────────────────────────────

  /// First warning dialog.
  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(AppLocalizations.of(context).profDeleteAccount,
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
          ],
        ),
        content: Text(
          AppLocalizations.of(context).profDeleteConfirmBody,
          textAlign: TextAlign.right,
          style: const TextStyle(height: 1.5, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).profCancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showFinalDeleteConfirmation(context);
            },
            child: Text(AppLocalizations.of(context).profContinue,
                style: TextStyle(
                    color: Colors.red[700], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Second (final) confirmation dialog with loading state.
  void _showFinalDeleteConfirmation(BuildContext context) {
    bool isDeleting = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(AppLocalizations.of(context).profFinalConfirm,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                const Icon(Icons.delete_forever_rounded, color: Colors.red),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppLocalizations.of(context).profDeleteFinalBody,
                  textAlign: TextAlign.right,
                  style: const TextStyle(height: 1.5, fontSize: 13),
                ),
                if (isDeleting) ...[
                  const SizedBox(height: 20),
                  const Center(
                      child: CircularProgressIndicator(color: Colors.red)),
                ],
              ],
            ),
            actions: isDeleting
                ? []
                : [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(AppLocalizations.of(context).profCancel)),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        setDialog(() => isDeleting = true);
                        await _deleteAccount(ctx);
                      },
                      child: Text(
                          AppLocalizations.of(context).profDeletePermanent,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
          );
        },
      ),
    );
  }

  /// Runs the full deletion flow via [AccountDeletionService] and handles
  /// every outcome: success, requires-recent-login, or unexpected error.
  Future<void> _deleteAccount(BuildContext dialogContext) async {
    final uid = _user?.uid ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (uid.isEmpty) return;

    final result = await AccountDeletionService.deleteAccount(uid);

    if (dialogContext.mounted) Navigator.pop(dialogContext);

    switch (result.outcome) {
      case DeletionOutcome.success:
        rootNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
          (_) => false,
        );

      case DeletionOutcome.requiresReauth:
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(AppLocalizations.of(context).profReauthNeeded,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                const Icon(Icons.lock_outline_rounded, color: Colors.orange),
              ],
            ),
            content: Text(
              AppLocalizations.of(context).profReauthBody,
              textAlign: TextAlign.right,
              style: const TextStyle(height: 1.5, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(context).profCancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await FirebaseAuth.instance.signOut();
                  rootNavigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const PhoneLoginScreen()),
                    (_) => false,
                  );
                },
                child:
                    Text(AppLocalizations.of(context).profLogoutAndReauth),
              ),
            ],
          ),
        );

      case DeletionOutcome.error:
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.profDeleteError(result.errorMessage ?? '')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }
}

/// Compact "פעיל" / "כבוי" status pill — replaces the round Switch thumb
/// across every toggle in this screen. Purely visual: the whole [ListTile]
/// row hosting it owns the tap (`onTap`), so the pill never double-fires a
/// toggle. Shows a spinner while an action is in flight.
class _OnOffPill extends StatelessWidget {
  final bool value;
  final bool loading;

  const _OnOffPill({required this.value, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final bg = value ? const Color(0xFF10B981) : const Color(0xFFE5E7EB);
    final fg = value ? Colors.white : const Color(0xFF6B7280);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 64,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFF6366F1)),
              ),
            )
          : Text(
              value ? 'פעיל' : 'כבוי',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
    );
  }
}
