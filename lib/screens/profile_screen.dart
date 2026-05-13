import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:convert';
import 'edit_profile_screen.dart';
import 'provider_registration_wizard_screen.dart';
import 'terms_of_service_screen.dart';
import 'privacy_policy_screen.dart';
import '../widgets/banners_admin/v3/vip_upgrade_button.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_provider.dart';
import '../services/cached_readers.dart';
import '../widgets/xp_progress_bar.dart';
import '../widgets/streak_badge.dart';
import '../widgets/community/heart_display_helper.dart';
import '../theme/community_theme.dart';
import '../utils/gold_heart_helper.dart';
import 'community/feature_flag.dart';
import '../widgets/anyskill_logo.dart';
import '../main.dart' show currentAppVersion;
import 'app_feedback_screen.dart';
import 'account_settings_screen.dart';
import 'favorites_screen.dart';
import 'service_history_screen.dart';
import 'phone_login_screen.dart';
import '../features/pet_stay/screens/dog_profile_list_screen.dart';
import '../services/user_roles.dart';
import 'role_switcher_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;

  // Single shared stream for the user doc — prevents duplicate Firestore reads.
  // Both AppBar and body StreamBuilders use this same stream.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots();

  // Incrementing this key forces StreamBuilder to recreate its subscription,
  // which is the recovery path after a transient Permission Denied error
  // (e.g., App Check token not yet ready on first load).
  int _streamKey = 0;

  @override
  void initState() {
    super.initState();
  }

  /// Safely converts a profileImage string (HTTP URL or base64 data URI)
  /// into an ImageProvider. Returns null if empty or malformed.
  static ImageProvider? _safeImageProvider(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return NetworkImage(raw);
    try {
      final b64 = raw.contains(',') ? raw.split(',').last : raw;
      return MemoryImage(base64Decode(b64));
    } catch (_) {
      debugPrint('[Profile] Failed to decode base64 image (${raw.length} chars)');
      return null;
    }
  }

  // ── Auto-sync profile image from Auth → Firestore (runs once) ─────────
  bool _syncAttempted = false;

  void _autoSyncProfileImage(Map<String, dynamic> data) {
    if (_syncAttempted) return;
    _syncAttempted = true;

    final firestoreImg = data['profileImage'] as String? ?? '';
    if (firestoreImg.isNotEmpty) return; // already has an image

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    // Try Auth photoURL first
    final authPhoto = authUser.photoURL ?? '';
    if (authPhoto.isEmpty) {
      debugPrint('[Profile] No image in Firestore AND no Auth photoURL — nothing to sync');
      return;
    }

    debugPrint('[Profile] Auto-syncing profileImage from Auth: $authPhoto');
    FirebaseFirestore.instance
        .collection('users')
        .doc(authUser.uid)
        .update({'profileImage': authPhoto})
        .then((_) => debugPrint('[Profile] profileImage synced to Firestore'))
        .catchError((e) => debugPrint('[Profile] Sync failed: $e'));
  }

  /// Manual sync — callable from a button for admins.
  Future<void> _forceResyncProfileImage() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    final messenger = ScaffoldMessenger.of(context);

    // Force refresh the Auth user to get the latest Google photoURL
    await authUser.reload();
    final refreshed = FirebaseAuth.instance.currentUser;
    final photoUrl = refreshed?.photoURL ?? '';

    if (photoUrl.isEmpty) {
      if (!mounted) return;
      final msg = AppLocalizations.of(context).profNoGooglePhoto;
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(authUser.uid)
        .update({'profileImage': photoUrl});

    // §61 invalidation contract: bust the 5-min cache so favorites,
    // chat header, BookingProfileAvatar etc. see the new avatar
    // instead of the stale one.
    CachedReaders.invalidateProvider(authUser.uid);

    _syncAttempted = false; // allow re-read on next stream event

    if (!mounted) return;
    final okMsg = AppLocalizations.of(context).profPhotoUpdatedFromGoogle;
    messenger.showSnackBar(SnackBar(
      content: Text(okMsg),
      backgroundColor: const Color(0xFF10B981),
    ));
  }

  // Email Invoice + Sound Mute toggles moved to AccountSettingsScreen.

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
      (route) => false,
    );
  }

  // ── Share profile ─────────────────────────────────────────────────────────
  void _shareProfile(String name, String uid, AppLocalizations l10n) async {
    final String profileLink = "https://anyskill-6fdf3.web.app/#/expert?id=$uid";
    final String shareText = "היי! מזמין אותך לצפות בפרופיל המקצועי שלי ב-AnySkill ולהזמין שירות מאובטח בנאמנות: $profileLink";

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(l10n.shareProfileTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF25D366), child: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20)),
              title: Text(l10n.shareProfileWhatsapp),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final whatsappUrl = "https://wa.me/?text=${Uri.encodeComponent(shareText)}";
                try {
                  if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                    await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
                  } else {
                    throw "Could not launch";
                  }
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(l10n.whatsappError)));
                }
              },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.copy, color: Colors.white)),
              title: Text(l10n.shareProfileCopyLink),
              onTap: () {
                Clipboard.setData(ClipboardData(text: profileLink));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.linkCopied)));
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Language selector ─────────────────────────────────────────────────────
  void _showLanguageSheet(BuildContext context, AppLocalizations l10n) {
    final current = LocaleProvider.instance.locale;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 16),
            Text(l10n.languageSectionLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            _langTile(ctx, const Locale('he'), '🇮🇱', l10n.languageHe, current),
            _langTile(ctx, const Locale('en'), '🇬🇧', l10n.languageEn, current),
            _langTile(ctx, const Locale('es'), '🇪🇸', l10n.languageEs, current),
            _langTile(ctx, const Locale('ar'), '🇸🇦', l10n.languageAr, current),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _langTile(BuildContext ctx, Locale locale, String flag, String name, Locale current) {
    final isSelected = current.languageCode == locale.languageCode;
    return ListTile(
      leading: Text(flag, style: const TextStyle(fontSize: 24)),
      title: Text(name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1))
          : null,
      selected: isSelected,
      selectedTileColor: const Color(0xFFF0F0FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      onTap: () {
        LocaleProvider.instance.setLocale(locale);
        Navigator.pop(ctx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userStream,
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final name = (data['name'] as String? ?? '').trim();
            final greeting = _greetingForNow(l10n);
            final text = name.isEmpty ? greeting : '$greeting $name';
            return Text(text,
                style: const TextStyle(fontWeight: FontWeight.bold));
          },
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _userStream,
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              final isProviderUser = (data['isProvider'] as bool? ?? false) ||
                                     (data['isSpecialist'] as bool? ?? false);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isProviderUser)
                    IconButton(
                      icon: const Icon(Icons.share_outlined, color: Colors.green),
                      onPressed: () => _shareProfile(data['name'] ?? l10n.defaultUserName, user?.uid ?? '', l10n),
                      tooltip: l10n.shareProfileTooltip,
                    ),
                  // Sync profile image from Google — visible when image is missing
                  if ((data['profileImage'] as String? ?? '').isEmpty)
                    IconButton(
                      icon: const Icon(Icons.sync_rounded, color: Colors.orange),
                      tooltip: AppLocalizations.of(context).profSyncGooglePhoto,
                      onPressed: _forceResyncProfileImage,
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF0047AB)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => EditProfileScreen(userData: data)),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        key: ValueKey(_streamKey),
        stream: _userStream,
        builder: (context, snapshot) {
          // Guard: auth state changed before AuthWrapper has redirected.
          if (FirebaseAuth.instance.currentUser == null) {
            return const SizedBox.shrink();
          }
          if (snapshot.hasError) {
            // Likely a transient Permission Denied while App Check token was
            // not yet ready. Show a retry button so the user can recover
            // without a full page reload.
            final l10nInner = AppLocalizations.of(context);
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    l10nInner.profileLoadError,
                    style: const TextStyle(fontSize: 15, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _streamKey++),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10nInner.retryButton),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          // ── Auto-sync: backfill profileImage from Auth if missing ──
          _autoSyncProfileImage(data);

          // Accept both field names — legacy docs may use 'isSpecialist'
          final isProvider = (data['isProvider'] as bool? ?? false) ||
                             (data['isSpecialist'] as bool? ?? false);

          // ── Customer gets the Airbnb-style redesigned screen ─────────────
          if (!isProvider) return _buildCustomerView(data, l10n);

          return SingleChildScrollView(
            child: Column(
              children: [
                // ── VIP upgrade card (provider only — pinned at top) ────────────
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      16, 12, 16, 0),
                  child: VipUpgradeButton(),
                ),
                // ── Airbnb-style specialist header ──────────────────────────────
              Builder(builder: (_) {
                // Try profileImage first, then fall back to Auth photoURL
                var profileImg = data['profileImage'] as String? ?? '';
                if (profileImg.isEmpty) {
                  profileImg = FirebaseAuth.instance.currentUser?.photoURL ?? '';
                }
                debugPrint('[Profile] email=${data['email']}, '
                    'profileImage=${profileImg.isEmpty ? "EMPTY" : profileImg.length > 80 ? "${profileImg.substring(0, 80)}..." : profileImg}');
                final ImageProvider? avatarImg = _safeImageProvider(profileImg);
                final name        = data['name'] as String? ?? l10n.defaultUserName;
                final isVerified  = data['isVerified'] as bool? ?? false;
                final serviceType = data['serviceType'] as String? ?? '';
                final aboutMe     = data['aboutMe'] as String? ?? '';
                // ── Legacy VIP fields removed ─────────────────────────────
                // The bottom VIP "action square" + `_showVipSheet()` + the
                // `activateVipSubscription` CF used `isPromoted` + 30-day
                // expiry. That system is being phased out in favor of the
                // top-of-screen `VipUpgradeButton` (§51 Banners Studio)
                // which writes to `vip_subscriptions/` and syncs the home
                // carousel. Two parallel VIP entry points caused a real
                // double-charge incident — provider paid via both buttons.
                // See CLAUDE.md §51 follow-up.
                final videoUrl    = data['verificationVideoUrl'] as String?;
                final videoApproved = data['videoVerifiedByAdmin'] as bool? ?? false;
                final hasVerifiedVideo = videoUrl != null && videoUrl.isNotEmpty && videoApproved;
                // Self-uploaded intro video (max 60s) — what the provider
                // controls themselves via the upload sheet on this screen.
                // Separate from `verificationVideoUrl` (admin-uploaded /
                // verified). When BOTH exist, we prefer the verified one
                // for the public profile but the provider can play/edit
                // their own from this screen.
                final introVideoUrl  = data['introVideoUrl'] as String? ?? '';
                final hasIntroVideo  = introVideoUrl.isNotEmpty;
                // The card is "active" (purple icon, opens player) if EITHER
                // the verified video or the self-uploaded intro video exists.
                final hasAnyVideo    = hasVerifiedVideo || hasIntroVideo;
                final playableVideoUrl = hasVerifiedVideo
                    ? videoUrl
                    : (hasIntroVideo ? introVideoUrl : null);

                return Column(
                  children: [
                    // ── Unified card: photo RIGHT / name+stats LEFT ──────
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 20,
                            spreadRadius: 0,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── LEFT: name, badge, title, bio, stats ──
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        if (isVerified) ...[
                                          const Icon(Icons.verified, color: Colors.blue, size: 18),
                                          const SizedBox(width: 5),
                                        ],
                                        Flexible(
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    // Role label — always visible for specialists
                                    Text(
                                      AppLocalizations.of(context).profProviderRole,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    if (serviceType.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(serviceType,
                                          style: const TextStyle(color: Color(0xFF6366F1), fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                    if (aboutMe.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(aboutMe,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12.5, height: 1.4)),
                                    ],
                                    const SizedBox(height: 14),
                                    _specialistStat(
                                      label: AppLocalizations.of(context).profJobsStat,
                                      value: '${(data['completedJobsCount'] as num? ?? data['reviewsCount'] as num? ?? 0).toInt()}',
                                      icon: Icons.shield_outlined,
                                      iconColor: const Color(0xFF6366F1),
                                    ),
                                    const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
                                    _specialistStat(
                                      label: AppLocalizations.of(context).profRatingStat,
                                      value: '${data['rating'] ?? '5.0'}',
                                      icon: Icons.star_rounded,
                                      iconColor: Colors.amber,
                                    ),
                                    const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
                                    _specialistStat(
                                      label: AppLocalizations.of(context).profReviewsStat,
                                      value: '${(data['reviewsCount'] as num? ?? 0).toInt()}',
                                      icon: Icons.chat_bubble_outline_rounded,
                                      iconColor: Colors.teal,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              // ── RIGHT: profile photo ──────────────────
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    radius: 52,
                                    backgroundColor: const Color(0xFFEEEBFF),
                                    backgroundImage: avatarImg,
                                    onBackgroundImageError: avatarImg != null ? (_, __) {} : null,
                                    child: avatarImg == null
                                        ? Icon(Icons.person, size: 44,
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.5))
                                        : null,
                                  ),
                                  // Phase C (v15.x): for v2 viewers with
                                  // an active gold heart, the bottom-end
                                  // overlay becomes the gold heart per
                                  // mockup 09. v1 viewers + non-active
                                  // hearts keep the legacy AnySkill brand
                                  // icon, untouched.
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: Builder(builder: (_) {
                                      final viewerUid =
                                          FirebaseAuth.instance.currentUser?.uid;
                                      final showGoldHeart =
                                          isCommunityV2EnabledFor(viewerUid) &&
                                              GoldHeartHelper
                                                  .hasActiveFromUserData(data);
                                      if (showGoldHeart) {
                                        return Container(
                                          width: 28,
                                          height: 28,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0x40A87F2A),
                                                blurRadius: 8,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.favorite,
                                            color: CommunityColors.goldHeart,
                                            size: 16,
                                          ),
                                        );
                                      }
                                      return Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.14),
                                                blurRadius: 5),
                                          ],
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const AnySkillBrandIcon(size: 20),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // ── XP Progress Bar ───────────────────────────
                          XpProgressBar(xp: (data['xp'] as num? ?? 0).toInt()),

                          // ── Streak Badge ───────────────────────────────
                          if ((data['streak'] as num? ?? 0).toInt() > 0) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: StreakBadge.fromUserData(data),
                            ),
                          ],

                          // ── Phase C (v15.x): gold-heart days-left bar ─────
                          // Mockup 09 element. Only shown to v2 viewers
                          // with an active heart — uses
                          // [GoldHeartHelper.daysUntilExpiry] which honours
                          // the legacy fallback during the rollout window.
                          if (isCommunityV2EnabledFor(
                                  FirebaseAuth.instance.currentUser?.uid) &&
                              GoldHeartHelper.hasActiveFromUserData(data)) ...[
                            const SizedBox(height: 14),
                            _GoldHeartActiveBar(userData: data),
                          ],

                          // ── Community / Volunteer Badge ──────────────────────
                          // Phase B (v15.x): viewer-gated. Own profile —
                          // viewerUid == ownerUid, so the gate behaves as
                          // expected (whitelisted owner sees v2 logic).
                          if (shouldShowHeartFor(
                            viewerUid: FirebaseAuth.instance.currentUser?.uid,
                            ownerData: data,
                          )) ...[
                            const SizedBox(height: 12),
                            Builder(builder: (_) {
                              final badges = data['communityBadges'] as List<dynamic>?;
                              final isAngel = badges != null && badges.contains('angel');
                              final isPillar = badges != null && badges.contains('pillar');
                              final badgeLabel = isAngel
                                  ? AppLocalizations.of(context).profAngelBadge
                                  : isPillar
                                      ? AppLocalizations.of(context).profPillarBadge
                                      : AppLocalizations.of(context).profStarterBadge;
                              final badgeIcon = isAngel
                                  ? Icons.auto_awesome_rounded
                                  : isPillar
                                      ? Icons.shield_rounded
                                      : Icons.favorite_rounded;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isAngel
                                        ? [const Color(0xFFF59E0B), const Color(0xFFEF4444)]
                                        : isPillar
                                            ? [const Color(0xFF6366F1), const Color(0xFFEC4899)]
                                            : [const Color(0xFFEF4444), const Color(0xFFEC4899)],
                                    begin: AlignmentDirectional.centerEnd,
                                    end: AlignmentDirectional.centerStart,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(badgeIcon, color: Colors.white, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      badgeLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Action squares: Gallery + Video Intro (side-by-side) ─
                    //
                    // Mirrors the public expert profile layout — two equal
                    // cards in a row so the provider gets visual parity
                    // with what customers see. Tap the video card to:
                    //   • play (when a video exists), OR
                    //   • open the upload sheet (when nothing's uploaded).
                    // Long-press the video card opens manage sheet
                    // (replace / delete) — owner-only.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          // Gallery card
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _SpecialistGalleryScreen(
                                      uid: user?.uid ?? ''),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.07),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 28, horizontal: 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo_library_outlined,
                                        size: 32, color: Colors.black),
                                    const SizedBox(height: 10),
                                    Text(
                                      AppLocalizations.of(context)
                                          .profWorkGallery,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Video Intro card (NEW — provider-controlled upload)
                          Expanded(
                            child: _ProviderVideoIntroCard(
                              uid: user?.uid ?? '',
                              introVideoUrl: introVideoUrl,
                              hasVerifiedVideo: hasVerifiedVideo,
                              verifiedVideoUrl: hasVerifiedVideo ? videoUrl : null,
                              hasAnyVideo: hasAnyVideo,
                              playableVideoUrl: playableVideoUrl,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                );
              }),

                // ── Language Selector ─────────────────────────────────────
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.language_rounded, color: Color(0xFF6366F1)),
                      title: Text(l10n.languageTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(_currentLangName(l10n),
                          style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Colors.grey),
                      onTap: () => _showLanguageSheet(context, l10n),
                    ),
                  ),
                ),

                // ── My Dogs (customers only) ──────────────────────────────
                if (data['isProvider'] != true && data['isPendingExpert'] != true) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.pets_rounded,
                              color: Color(0xFF6366F1)),
                        ),
                        title: Text(AppLocalizations.of(context).profMyDogs,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(AppLocalizations.of(context).profMyDogsSubtitle,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded,
                            size: 15, color: Colors.grey),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DogProfileListScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // ── Join as Provider CTA (clients only) ──
                if (data['isProvider'] != true && data['isPendingExpert'] != true) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProviderRegistrationWizardScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.work_outline_rounded,
                          size: 18, color: Color(0xFF6366F1)),
                      label: Text(
                        AppLocalizations.of(context).profJoinAsProvider,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        side: const BorderSide(
                            color: Color(0xFF6366F1), width: 1.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (data['isPendingExpert'] == true) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFFBBF24), width: 1.2),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          const Icon(Icons.hourglass_top_rounded,
                              color: Color(0xFFF59E0B), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context).profRequestInReview,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // ── Legal links ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                            const TermsOfServiceScreen(showAcceptButton: false))),
                        child: Text(AppLocalizations.of(context).profTermsOfService,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6366F1))),
                      ),
                      Text(' • ', style: TextStyle(color: Colors.grey[400])),
                      TextButton(
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                            const PrivacyPolicyScreen())),
                        child: Text(AppLocalizations.of(context).profPrivacyPolicy,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6366F1))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── Switch Role (multi-role users only) ───────────────────
                Builder(builder: (_) {
                  final roles = UserRoles.fromUserDoc(data);
                  if (!roles.hasMultiple) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25)
                        .copyWith(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const RoleSwitcherScreen(allowBack: true),
                        ),
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded,
                          size: 18, color: Color(0xFF8B5CF6)),
                      label: Text(AppLocalizations.of(context).profSwitchRole,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8B5CF6))),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        side: const BorderSide(
                            color: Color(0xFF8B5CF6), width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  );
                }),
                // ── Account Settings ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AccountSettingsScreen()),
                    ),
                    icon: const Icon(Icons.manage_accounts_rounded,
                        size: 18, color: Color(0xFF6366F1)),
                    label: const Text(
                      'הגדרות חשבון',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1)),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(
                          color: Color(0xFF6366F1), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Logout ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF6366F1)),
                    label: Text(AppLocalizations.of(context).profLogout,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Feedback & Ideas ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AppFeedbackScreen()),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded,
                        size: 18, color: Color(0xFF6366F1)),
                    label: const Text(
                      'הצעות ורעיונות לשיפור',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1)),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(
                          color: Color(0xFF6366F1), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Terms of Use & Privacy Policy ─────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TermsOfServiceScreen(
                              showAcceptButton: false)),
                    ),
                    icon: const Icon(Icons.description_outlined,
                        size: 18, color: Color(0xFF6366F1)),
                    label: const Text(
                      'תנאי שימוש ומדיניות הפרטיות',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1)),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(
                          color: Color(0xFF6366F1), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'AnySkill v$currentAppVersion',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    );
  }

  String _greetingForNow(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return l10n.greetingMorning;
    if (h >= 12 && h < 17) return l10n.greetingAfternoon;
    if (h >= 17 && h < 21) return l10n.greetingEvening;
    return l10n.greetingNight;
  }

  String _currentLangName(AppLocalizations l10n) {
    switch (LocaleProvider.instance.locale.languageCode) {
      case 'en': return '🇬🇧 ${l10n.languageEn}';
      case 'es': return '🇪🇸 ${l10n.languageEs}';
      case 'ar': return '🇸🇦 ${l10n.languageAr}';
      default:   return '🇮🇱 ${l10n.languageHe}';
    }
  }

  // ── Customer Profile Screen (Airbnb-style) ──────────────────────────────

  /// Fetches the count of jobs completed by this customer.
  /// TODO: replace with AggregateQuery once cloud_firestore supports it
  ///       cleanly on web (currently falls back to document read).
  Future<int> _fetchCompletedBookingsCount(String uid) async {
    if (uid.isEmpty) return 0;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .limit(999)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }


  Widget _customerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.start,
          style: const TextStyle(
            fontSize: 11.5,
            color: Colors.black,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerView(Map<String, dynamic> data, AppLocalizations l10n) {
    final uid        = user?.uid ?? '';
    var profileImg = data['profileImage'] as String? ?? '';
    if (profileImg.isEmpty) {
      profileImg = FirebaseAuth.instance.currentUser?.photoURL ?? '';
    }
    final ImageProvider? custAvatarImg = _safeImageProvider(profileImg);
    final name       = data['name'] as String? ?? l10n.defaultUserName;

    // Years in AnySkill — derived from the createdAt timestamp on the user doc.
    // TODO: fall back to registration date once reliably written for all users.
    final createdAt  = data['createdAt'] as Timestamp?;
    final yearsInApp = createdAt != null
        ? ((DateTime.now().difference(createdAt.toDate()).inDays) / 365.25)
            .floor()
        : 0;

    // Avatar Stack — extracted so it's used as first child of the RTL Row.
    final avatarStack = Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 52,
          backgroundColor: const Color(0xFFEEEBFF),
          backgroundImage: custAvatarImg,
          onBackgroundImageError: custAvatarImg != null ? (_, __) {} : null,
          child: custAvatarImg == null
              ? Icon(Icons.person,
                  size: 44,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.5))
              : null,
        ),
        // AnySkill brand badge — bottom-right of avatar circle
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: const AnySkillBrandIcon(size: 20),
          ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        // CrossAxisAlignment.start = physical RIGHT in the app's RTL Directionality.
        // This pins the "פרופיל" heading and all children to the far-right edge.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Large heading — far right ───────────────────────────────────
          Text(
            AppLocalizations.of(context).profTitle,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),

          // ── Airbnb-style floating stats card ────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Row(
              // LTR Row: first child → LEFT (photo), second child → RIGHT (stats).
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── LEFT: avatar · name · לקוח/ה ────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatarStack,
                    const SizedBox(height: 12),
                    Text(
                      name,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      AppLocalizations.of(context).profCustomerRole,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),

                // ── RIGHT: 3 vertical stats ──────────────────────────────
                FutureBuilder<int>(
                  future: _fetchCompletedBookingsCount(uid),
                  builder: (ctx, snap) {
                    final services = snap.data ?? 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _customerStat(AppLocalizations.of(context).profStatServicesTaken, services.toString()),
                        const Divider(height: 24, color: Color(0xFFF3F4F6), thickness: 1),
                        _customerStat(AppLocalizations.of(context).profStatReviews, '0'), // TODO: reviews count
                        const Divider(height: 24, color: Color(0xFFF3F4F6), thickness: 1),
                        _customerStat(AppLocalizations.of(context).profStatYears, yearsInApp.toString()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Join as Provider CTA — moved above-the-fold for visibility ──
          if ((data['isProvider'] != true) &&
              (data['isSpecialist'] != true) &&
              (data['isPendingExpert'] != true))
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProviderRegistrationWizardScreen(),
                  ),
                ),
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 18, horizontal: 18),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(Icons.work_outline_rounded,
                          color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).profJoinAsProvider,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_back_rounded,
                          color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          if ((data['isProvider'] != true) &&
              (data['isSpecialist'] != true) &&
              (data['isPendingExpert'] != true))
            const SizedBox(height: 16),

          // ── Two-card row: Services + Favorites ──────────────────────────
          Row(
            children: [
              // Right card: שירות שהתקבל
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ServiceHistoryScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 20,
                          spreadRadius: 0,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.assignment_turned_in_outlined, size: 32, color: Colors.black),
                        const SizedBox(height: 10),
                        Text(
                          AppLocalizations.of(context).profReceivedService,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Left card: מועדפים
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FavoritesScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 20,
                          spreadRadius: 0,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_border, size: 32, color: Colors.black),
                        const SizedBox(height: 10),
                        Text(
                          AppLocalizations.of(context).profFavorites,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Language Selector ─────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListTile(
              leading: const Icon(Icons.language_rounded, color: Color(0xFF6366F1)),
              title: Text(l10n.languageTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_currentLangName(l10n),
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Colors.grey),
              onTap: () => _showLanguageSheet(context, l10n),
            ),
          ),

          const SizedBox(height: 16),

          // ── Account Settings ─────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AccountSettingsScreen()),
            ),
            icon: const Icon(Icons.manage_accounts_rounded,
                size: 18, color: Color(0xFF6366F1)),
            label: const Text(
              'הגדרות חשבון',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 12),

          // ── Logout ───────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF6366F1)),
            label: Text(
              AppLocalizations.of(context).profLogout,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 12),

          // ── Feedback & Ideas ───────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AppFeedbackScreen()),
            ),
            icon: const Icon(Icons.auto_awesome_rounded,
                size: 18, color: Color(0xFF6366F1)),
            label: const Text(
              'הצעות ורעיונות לשיפור',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1)),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side:
                  const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 12),

          // ── Terms of Use & Privacy Policy ────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const TermsOfServiceScreen(showAcceptButton: false)),
            ),
            icon: const Icon(Icons.description_outlined,
                size: 18, color: Color(0xFF6366F1)),
            label: const Text(
              'תנאי שימוש ומדיניות הפרטיות',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            'AnySkill v$currentAppVersion',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // _showVipSheet removed — was the bottom legacy VIP entry point that
  // called `activateVipSubscription` CF (legacy `isPromoted` system).
  // Replaced by the top-of-profile `VipUpgradeButton` widget which calls
  // `purchaseVipWithCredits` and syncs the home tab carousel via
  // `_runVipCarouselSync`. Removing this method also kills the
  // duplicate-payment bug. See CLAUDE.md §51 follow-up.

  /// Stat row used in the specialist Airbnb card:
  /// bold number + small coloured icon to its right + grey label below.
  Widget _specialistStat({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 16, color: iconColor),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: Colors.black54,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _SpecialistGalleryScreen — live gallery backed by the user's Firestore doc
// ═══════════════════════════════════════════════════════════════════════════

class _SpecialistGalleryScreen extends StatelessWidget {
  const _SpecialistGalleryScreen({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).profWorkGallery,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final gallery = (data['gallery'] as List<dynamic>?) ?? [];

          if (gallery.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[350]),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context).profNoWorksYet,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Colors.grey, height: 1.6),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.builder(
              itemCount: gallery.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final imgData = gallery[index].toString();
                final isUrl = imgData.startsWith('http');
                // Safely decode base64 OUTSIDE the build — if the stored
                // string isn't valid base64 we fall through to the
                // placeholder instead of crashing with FormatException.
                Uint8List? decodedBytes;
                if (!isUrl) {
                  try {
                    final b64 = imgData.contains(',')
                        ? imgData.split(',').last
                        : imgData;
                    decodedBytes = base64Decode(b64);
                  } catch (_) {
                    decodedBytes = null;
                  }
                }
                Widget brokenPlaceholder() => Container(
                      color: Colors.grey[200],
                      child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey,
                          size: 40),
                    );
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: isUrl
                      ? Image.network(
                          imgData,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : Container(
                                  color: Colors.grey[200],
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                          errorBuilder: (_, __, ___) => brokenPlaceholder(),
                        )
                      : (decodedBytes != null
                          ? Image.memory(
                              decodedBytes,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => brokenPlaceholder(),
                            )
                          : brokenPlaceholder()),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Provider-owned video intro card — sits next to the gallery card on the
// provider's own profile screen.
//
// States:
//   ▸ no video yet            → indigo "+" CTA "הוסף וידאו היכרות"
//   ▸ self-uploaded intro     → purple play icon, tap to play, long-press
//                                opens manage sheet (replace / delete)
//   ▸ admin-verified video    → same as above + verified checkmark badge.
//                                In this state, "delete" only clears
//                                `introVideoUrl` — the verified video
//                                survives until the admin reverifies.
//
// Upload contract:
//   path:     `intro_videos/{uid}/v_{ts}.{ext}`
//   max:      60 seconds (enforced by ImagePicker.pickVideo.maxDuration)
//   storage:  ≤ 50 MB (matches storage.rules:65)
//   firestore: writes `users/{uid}.introVideoUrl` (and timestamps the
//              upload via `introVideoUploadedAt`)
//
// Old uploads on Storage are NOT cleaned up automatically — each save
// creates a new timestamped file. A future janitor CF can sweep stale
// `intro_videos/{uid}/v_*` entries that aren't the current
// `introVideoUrl`. Not critical at our scale.
// ════════════════════════════════════════════════════════════════════════════
class _ProviderVideoIntroCard extends StatefulWidget {
  const _ProviderVideoIntroCard({
    required this.uid,
    required this.introVideoUrl,
    required this.hasVerifiedVideo,
    required this.verifiedVideoUrl,
    required this.hasAnyVideo,
    required this.playableVideoUrl,
  });

  final String uid;
  final String introVideoUrl;
  final bool hasVerifiedVideo;
  final String? verifiedVideoUrl;
  final bool hasAnyVideo;
  final String? playableVideoUrl;

  @override
  State<_ProviderVideoIntroCard> createState() =>
      _ProviderVideoIntroCardState();
}

class _ProviderVideoIntroCardState extends State<_ProviderVideoIntroCard> {
  bool _busy = false;

  Future<void> _onPrimaryTap() async {
    if (_busy) return;
    // Has a video → play it. Empty → start upload.
    if (widget.hasAnyVideo && widget.playableVideoUrl != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _VideoIntroScreen(videoUrl: widget.playableVideoUrl!),
        ),
      );
    } else {
      await _pickAndUpload();
    }
  }

  Future<void> _onLongPress() async {
    // No manage menu when nothing has been uploaded yet.
    if (!widget.hasAnyVideo) return;
    await _showManageSheet();
  }

  Future<void> _showManageSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                AppLocalizations.of(context).profVideoIntro,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (widget.playableVideoUrl != null)
              ListTile(
                leading: const Icon(Icons.play_circle_fill_rounded,
                    color: Color(0xFF6366F1)),
                title: const Text('נגן וידאו',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _VideoIntroScreen(
                          videoUrl: widget.playableVideoUrl!),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded,
                  color: Color(0xFF6366F1)),
              title: const Text('החלף וידאו',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('עד 60 שניות',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUpload();
              },
            ),
            // Allow delete ONLY when there's a self-uploaded video.
            // The admin-verified one is untouchable from here.
            if (widget.introVideoUrl.isNotEmpty)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('מחק וידאו',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDelete();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('למחוק את הוידאו?',
            textDirection: TextDirection.rtl),
        content: const Text(
          'הוידאו יוסר מהפרופיל הציבורי שלך. הקובץ עצמו לא יימחק מההיסטוריה ויהיה ניתן להעלות חדש בכל עת.',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('בטל'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'introVideoUrl': FieldValue.delete(),
        'introVideoUploadedAt': FieldValue.delete(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הוידאו נמחק')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה במחיקה: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    if (widget.uid.isEmpty) return;
    setState(() => _busy = true);
    try {
      final XFile? file = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 1),
      );
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final Uint8List bytes = await file.readAsBytes();
      final ext = _extForName(file.name);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref()
          .child('intro_videos/${widget.uid}/v_$ts.$ext');
      final metadata = SettableMetadata(contentType: _mimeForExt(ext));
      await ref.putData(bytes, metadata);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'introVideoUrl': url,
        'introVideoUploadedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הוידאו הועלה בהצלחה ✨')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בהעלאה: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _extForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mov')) return 'mov';
    if (lower.endsWith('.webm')) return 'webm';
    if (lower.endsWith('.m4v')) return 'm4v';
    return 'mp4';
  }

  static String _mimeForExt(String ext) {
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return 'video/mp4';
    }
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6366F1);
    final hasVideo = widget.hasAnyVideo;
    final iconData = hasVideo
        ? Icons.play_circle_outline_rounded
        : Icons.video_call_rounded;
    final iconColor = _busy ? Colors.grey[400]! : purple;
    final label = hasVideo
        ? AppLocalizations.of(context).profVideoIntro
        : 'הוסף וידאו היכרות';

    return InkWell(
      onTap: _busy ? null : _onPrimaryTap,
      onLongPress: _busy ? null : _onLongPress,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding:
            const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _busy
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: purple),
                      )
                    : Icon(iconData, size: 32, color: iconColor),
                if (widget.hasVerifiedVideo && !_busy)
                  PositionedDirectional(
                    bottom: -4,
                    end: -6,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(1),
                      child: const Icon(Icons.verified_rounded,
                          size: 14, color: Color(0xFF22C55E)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasVideo ? Colors.black : purple,
              ),
            ),
            if (!hasVideo) ...[
              const SizedBox(height: 4),
              const Text(
                'עד 60 שניות',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ── Full-screen video intro player ───────────────────────────────────────────
class _VideoIntroScreen extends StatefulWidget {
  final String videoUrl;
  const _VideoIntroScreen({required this.videoUrl});

  @override
  State<_VideoIntroScreen> createState() => _VideoIntroScreenState();
}

class _VideoIntroScreenState extends State<_VideoIntroScreen> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _ctrl.play();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(AppLocalizations.of(context).profVideoIntro,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: _initialized
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
                  });
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _ctrl.value.aspectRatio,
                      child: VideoPlayer(_ctrl),
                    ),
                    if (!_ctrl.value.isPlaying)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 48),
                      ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mockup 09 element: "לב זהב פעיל · עוד X ימים" bar.
//
// Rendered above the existing community-badge gradient on the user's own
// profile, only for v2 viewers with an active gold heart. Visual style
// matches the gradient gold container in mockup 09 (no progress bar — the
// progress fraction lives on `MyVolunteeringScreen` per mockup 07).
// ─────────────────────────────────────────────────────────────────────────────
class _GoldHeartActiveBar extends StatelessWidget {
  const _GoldHeartActiveBar({required this.userData});
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final daysLeft = GoldHeartHelper.daysUntilExpiryFromUserData(userData);
    if (daysLeft == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x10A87F2A), // gold @ 6%
            Color(0x05A87F2A), // gold @ 2%
          ],
        ),
        border: Border.all(
          color: const Color(0x33A87F2A), // gold @ 20%
          width: 0.5,
        ),
        borderRadius: const BorderRadius.all(CommunityRadius.field),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.favorite,
            size: 14,
            color: CommunityColors.goldHeart,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'לב זהב פעיל',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'מתנדב/ת פעיל/ה · עוד $daysLeft ימים',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.textTertiary,
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

