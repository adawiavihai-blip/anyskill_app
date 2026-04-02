import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';
import 'edit_profile_screen.dart';
import 'provider_registration_screen.dart';
import 'terms_of_service_screen.dart';
import '../widgets/vip_confetti.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_provider.dart';
import '../services/account_deletion_service.dart';
import '../services/volunteer_service.dart';
import '../widgets/xp_progress_bar.dart';
import '../widgets/streak_badge.dart';
import '../widgets/anyskill_logo.dart';
import '../main.dart' show currentAppVersion, rootNavigatorKey;
import 'favorites_screen.dart';
import 'phone_login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;

  // Incrementing this key forces StreamBuilder to recreate its subscription,
  // which is the recovery path after a transient Permission Denied error
  // (e.g., App Check token not yet ready on first load).
  int _streamKey = 0;

  @override
  void initState() {
    super.initState();
  }

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
        title: Text(l10n.profileTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
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
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
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
          // Accept both field names — legacy docs may use 'isSpecialist'
          final isProvider = (data['isProvider'] as bool? ?? false) ||
                             (data['isSpecialist'] as bool? ?? false);

          // ── Customer gets the Airbnb-style redesigned screen ─────────────
          if (!isProvider) return _buildCustomerView(data, l10n);

          return SingleChildScrollView(
            child: Column(
              children: [
                // ── Airbnb-style specialist header ──────────────────────────────
              Builder(builder: (_) {
                final profileImg  = data['profileImage'] as String? ?? '';
                final hasImg      = profileImg.isNotEmpty;
                final ImageProvider? avatarImg = hasImg
                    ? (profileImg.startsWith('http')
                        ? NetworkImage(profileImg)
                        : MemoryImage(base64Decode(profileImg.split(',').last)))
                    : null;
                final name        = data['name'] as String? ?? l10n.defaultUserName;
                final isVerified  = data['isVerified'] as bool? ?? false;
                final serviceType = data['serviceType'] as String? ?? '';
                final aboutMe     = data['aboutMe'] as String? ?? '';
                final isPromoted  = data['isPromoted'] as bool? ?? false;
                final expiryTs    = data['promotionExpiryDate'] as Timestamp?;
                final expiryDate  = expiryTs?.toDate();
                final now         = DateTime.now();
                final isVipActive = isPromoted && expiryDate != null && expiryDate.isAfter(now);
                final videoUrl    = data['verificationVideoUrl'] as String?;
                final videoApproved = data['videoVerifiedByAdmin'] as bool? ?? false;
                final hasVerifiedVideo = videoUrl != null && videoUrl.isNotEmpty && videoApproved;

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
                                    const Text(
                                      'נותן שירות',
                                      style: TextStyle(
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
                                      label: 'עבודות',
                                      value: '${(data['completedJobsCount'] as num? ?? data['reviewsCount'] as num? ?? 0).toInt()}',
                                      icon: Icons.shield_outlined,
                                      iconColor: const Color(0xFF6366F1),
                                    ),
                                    const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
                                    _specialistStat(
                                      label: 'דירוג',
                                      value: '${data['rating'] ?? '5.0'}',
                                      icon: Icons.star_rounded,
                                      iconColor: Colors.amber,
                                    ),
                                    const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
                                    _specialistStat(
                                      label: 'ביקורות',
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
                                          BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 5),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const AnySkillBrandIcon(size: 20),
                                    ),
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

                          // ── Dynamic Volunteer Badge (active if task in last 30d) ──
                          if (VolunteerService.hasActiveVolunteerBadge(data)) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFF6366F1)],
                                  begin: AlignmentDirectional.centerEnd,
                                  end: AlignmentDirectional.centerStart,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.volunteer_activism, color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'מתנדב פעיל',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Action squares: Gallery + VIP (+ Video if approved) ─────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          // Right square: גלריית עבודות
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _SpecialistGalleryScreen(uid: user?.uid ?? ''))),
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
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.photo_library_outlined, size: 32, color: Colors.black),
                                    SizedBox(height: 10),
                                    Text(
                                      'גלריית עבודות',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Left square: VIP
                          Expanded(
                            child: InkWell(
                              onTap: () => _showVipSheet(context, data, l10n),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isVipActive ? const Color(0xFFFBBF24) : Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.07),
                                      blurRadius: 20,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                  border: isVipActive ? null : Border.all(color: Colors.grey.shade200),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.workspace_premium_rounded,
                                      size: 32,
                                      color: isVipActive ? Colors.white : Colors.amber[700],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      isVipActive ? 'VIP פעיל' : 'הצטרף ל-VIP',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isVipActive ? Colors.white : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Video Intro square (only when approved) ────────────
                    if (hasVerifiedVideo) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _VideoIntroScreen(videoUrl: videoUrl),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'היכרות בווידאו',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.verified_rounded, size: 16, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

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

                // ── Earn money CTA (clients only — hidden for providers/pending) ──
                if (data['isProvider'] != true && data['isPendingExpert'] != true) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProviderRegistrationScreen(
                            isExistingUser: true,
                            prefillData: {
                              'uid':         user?.uid ?? '',
                              'name':        data['name'] ?? '',
                              'phone':       data['phone'] ?? '',
                              'email':       data['email'] ?? '',
                              'profileImage': data['profileImage'] ?? '',
                              'aboutMe':     data['aboutMe'] ?? '',
                              'serviceType': data['serviceType'] ?? '',
                              'pricePerHour': data['pricePerHour'] ?? 0,
                            },
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF059669), Color(0xFF10B981)],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF059669).withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.attach_money_rounded,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('רוצה להרוויח כסף?',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  Text('הצטרף כנותן שירות ותתחיל להרוויח',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white70, size: 14),
                          ],
                        ),
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
                      child: const Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Icon(Icons.hourglass_top_rounded,
                              color: Color(0xFFF59E0B), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'הבקשה שלך בבדיקה — נעדכן בהקדם',
                              textAlign: TextAlign.right,
                              style: TextStyle(
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
                        child: const Text('תנאי שימוש',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6366F1))),
                      ),
                      Text(' • ', style: TextStyle(color: Colors.grey[400])),
                      TextButton(
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                            const TermsOfServiceScreen(showAcceptButton: false))),
                        child: const Text('מדיניות פרטיות',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6366F1))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── Logout ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF6366F1)),
                    label: const Text('התנתקות',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Delete Account ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: OutlinedButton.icon(
                    onPressed: () => _showDeleteAccountDialog(context),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18, color: Colors.red),
                    label: const Text('מחיקת חשבון',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: Colors.red, width: 1.5),
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

  /// A single vertical stat cell — bold black number, black label.
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
    final profileImg = data['profileImage'] as String? ?? '';
    final hasImg     = profileImg.isNotEmpty;
    final ImageProvider? custAvatarImg = hasImg
        ? (profileImg.startsWith('http')
            ? NetworkImage(profileImg)
            : MemoryImage(base64Decode(profileImg.split(',').last)))
        : null;
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
          const Text(
            'פרופיל',
            style: TextStyle(
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
                    const Text(
                      'לקוח/ה',
                      style: TextStyle(
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
                        _customerStat('שירותים שנלקחו', services.toString()),
                        const Divider(height: 24, color: Color(0xFFF3F4F6), thickness: 1),
                        _customerStat('ביקורות', '0'), // TODO: reviews count
                        const Divider(height: 24, color: Color(0xFFF3F4F6), thickness: 1),
                        _customerStat('שנים ב-AnySkill', yearsInApp.toString()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Two-card row: Services + Favorites ──────────────────────────
          Row(
            children: [
              // Right card: שירות שהתקבל
              Expanded(
                child: InkWell(
                  onTap: () {},
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
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_turned_in_outlined, size: 32, color: Colors.black),
                        SizedBox(height: 10),
                        Text(
                          'שירות שהתקבל',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_border, size: 32, color: Colors.black),
                        SizedBox(height: 10),
                        Text(
                          'מועדפים',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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

          const SizedBox(height: 16),

          // ── Monetization banner ──────────────────────────────────────────
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.monetization_on_outlined, color: Colors.white, size: 26),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'רוצה להרויח כסף? לחץ כאן',
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

          // ── Logout ───────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF6366F1)),
            label: const Text(
              'התנתקות',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 12),

          // ── Delete Account ───────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => _showDeleteAccountDialog(context),
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            label: const Text(
              'מחיקת חשבון',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: Colors.red, width: 1.5),
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

  void _showVipSheet(BuildContext context, Map<String, dynamic> data, AppLocalizations l10n) {
    final balance = (data['balance'] as num? ?? 0).toDouble();
    final hasBalance = balance >= 99;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFB347), Color(0xFFFFCC02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Text(l10n.vipSheetHeader, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("₪", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const Text("99", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.black87, height: 1)),
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(l10n.vipPriceMonthly, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "${l10n.statBalance}: ₪${balance.toStringAsFixed(0)}",
                style: TextStyle(color: hasBalance ? Colors.green[600] : Colors.red[600], fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.amber.shade200)),
                child: Column(
                  children: [
                    ("🏆", l10n.vipBenefit1),
                    ("✨", l10n.vipBenefit2),
                    ("📈", l10n.vipBenefit3),
                    ("🔥", l10n.vipBenefit4),
                  ].map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(b.$2, style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(b.$1, style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      )).toList(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasBalance ? const Color(0xFFFFC300) : Colors.grey[300],
                    foregroundColor: hasBalance ? Colors.black87 : Colors.grey[500],
                    minimumSize: const Size(double.infinity, 58),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: hasBalance && !isLoading
                      ? () async {
                          setSheet(() => isLoading = true);
                          try {
                            await FirebaseFunctions.instance.httpsCallable('activateVipSubscription').call();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              VipConfetti.show(context);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                backgroundColor: const Color(0xFFFFC300),
                                content: Text(l10n.vipActivationSuccess,
                                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                                duration: const Duration(seconds: 4),
                              ));
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setSheet(() => isLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(backgroundColor: Colors.red, content: Text("${l10n.errorGeneric}: $e")),
                              );
                            }
                          }
                        }
                      : null,
                  child: isLoading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black87))
                      : Text(
                          hasBalance ? l10n.vipActivateButton : l10n.vipInsufficientBalance,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              if (!hasBalance) ...[
                const SizedBox(height: 10),
                Text(l10n.vipInsufficientTooltip,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Account Deletion ──────────────────────────────────────────────────────

  /// Single-step deletion dialog — used by the AppBar trash-can icon.
  /// Visible to ALL user types. Calls _deleteAccount directly on confirm.
  /// First warning dialog.
  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('מחיקת חשבון',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
          ],
        ),
        content: const Text(
          'האם אתה בטוח שברצונך למחוק את חשבונך?\n\n'
          'כל הנתונים — ההיסטוריה, הארנק, הצ׳אטים — ימחקו לצמיתות.\n\n'
          'פעולה זו אינה הפיכה.',
          textAlign: TextAlign.right,
          style: TextStyle(height: 1.5, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showFinalDeleteConfirmation(context);
            },
            child: Text('המשך',
                style: TextStyle(
                    color: Colors.red[700], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Second (final) confirmation dialog with loading state.
  void _showFinalDeleteConfirmation(BuildContext context) {
    bool isDeleting = false;   // hoisted so StatefulBuilder sees mutations
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('אישור סופי',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.delete_forever_rounded, color: Colors.red),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'לאחר האישור, חשבונך ימחק לצמיתות ולא ניתן יהיה לשחזרו.',
                  textAlign: TextAlign.right,
                  style: TextStyle(height: 1.5, fontSize: 13),
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
                        child: const Text('ביטול')),
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
                      child: const Text('מחק לצמיתות',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
    final uid       = user?.uid ?? '';
    final messenger = ScaffoldMessenger.of(context);
    if (uid.isEmpty) return;

    final result = await AccountDeletionService.deleteAccount(uid);

    // Always pop the confirmation dialog first.
    if (dialogContext.mounted) Navigator.pop(dialogContext);

    switch (result.outcome) {
      case DeletionOutcome.success:
        // Auth user is gone — navigate to the login screen and clear the stack.
        rootNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
          (_) => false,
        );

      case DeletionOutcome.requiresReauth:
        // Firebase rejected delete() because the session is too old.
        // Show an explanatory dialog; user must sign out, re-login, then retry.
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('נדרשת כניסה מחדש',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.lock_outline_rounded, color: Colors.orange),
              ],
            ),
            content: const Text(
              'לצורך מחיקת חשבון, Firebase דורש שנכנסת לאחרונה.\n\n'
              'אנא התנתק, היכנס מחדש ונסה שוב.',
              textAlign: TextAlign.right,
              style: TextStyle(height: 1.5, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ביטול'),
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
                child: const Text('התנתק והיכנס מחדש'),
              ),
            ],
          ),
        );

      case DeletionOutcome.error:
        messenger.showSnackBar(SnackBar(
          content: Text('שגיאה במחיקת החשבון: ${result.errorMessage}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }
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
        title: const Text(
          'גלריית עבודות',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                    const Text(
                      'עדיין לא העלית עבודות.\nלחץ על העיפרון כדי לעדכן!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.6),
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
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
                          ),
                        )
                      : Image.memory(
                          base64Decode(imgData.contains(',') ? imgData.split(',').last : imgData),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
                          ),
                        ),
                );
              },
            ),
          );
        },
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
        title: const Text('היכרות בווידאו',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

