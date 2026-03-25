import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';
import 'chat_list_screen.dart';
import 'system_wallet_screen.dart';
import 'finance_screen.dart';
import 'my_bookings_screen.dart';
import 'opportunities_screen.dart';
import 'my_requests_screen.dart';
import '../services/location_service.dart';
import '../services/ai_analysis_service.dart';
import '../services/matchmaker_service.dart';
import '../services/opportunity_hunter_service.dart';
import '../services/audio_service.dart';
import '../services/cache_service.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import '../onboarding/app_tour.dart';
import '../main.dart' show PendingNotification;
import 'home_tab.dart';
import '../constants.dart' show resolveCanonicalCategory;
import '../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int    _selectedIndex   = 0;
  double _tabFadeOpacity  = 1.0;   // drives fade-in animation on tab switch
  final User? currentUser = FirebaseAuth.instance.currentUser;

  /// One navigator key per tab slot (max 8 tabs: 5 common + opp + admin + system).
  final List<GlobalKey<NavigatorState>> _tabNavKeys =
      List.generate(8, (_) => GlobalKey<NavigatorState>());
  final String adminEmail = "adawiavihai@gmail.com";

  // ── Badge counters ─────────────────────────────────────────────────────────
  int _bookingsCustBadge   = 0;  // jobs needing customer approval (expert_completed)
  int _bookingsExpertBadge = 0;  // jobs needing expert to finish (paid_escrow)
  int _opportunitiesBadge  = 0;  // new job_requests in provider's category
  int get _bookingsBadge => _bookingsCustBadge + _bookingsExpertBadge;

  // ── Bookings badge "seen" logic ───────────────────────────────────────────
  // Stores the count at the time the user last opened the Bookings tab.
  // The visible badge = max(0, _bookingsBadge - _bookingsLastCleared).
  // Resets to 0 when tapped, reappears only when new actionable jobs arrive.
  int _bookingsLastCleared = 0;
  int get _bookingsVisibleBadge => (_bookingsBadge - _bookingsLastCleared).clamp(0, 999);

  // ── Tour ────────────────────────────────────────────────────────────────────
  /// Context inside the ShowCaseWidget tree — used to call startShowCase().
  BuildContext? _showcaseCtx;
  bool _tourStarted     = false;
  bool _tourLocallyDone = false; // fast local guard, loaded from SharedPreferences

  StreamSubscription<QuerySnapshot>? _bookingsCustSub;
  StreamSubscription<QuerySnapshot>? _bookingsExpertSub;
  StreamSubscription<QuerySnapshot>? _opportunitiesSub;

  String    _oppServiceType = '';   // cached to detect serviceType changes
  Timestamp? _oppLastViewed;        // users/{uid}.lastViewedOpportunitiesAt

  // Streams מאוחסנים ב-initState — מניעת subscribe/unsubscribe מחדש בכל rebuild
  late final Stream<DocumentSnapshot> _userStream;
  late final Stream<QuerySnapshot> _chatStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnlineStatus(true);
    final uid = currentUser?.uid;
    if (uid != null) LocationService.init(uid);
    if (uid != null) OpportunityHunterService.markActive(uid);
    // Load local tour-complete flag so the tour is suppressed even before
    // the Firestore user doc arrives (prevents a flash on slow connections).
    SharedPreferences.getInstance().then((p) {
      if (p.getBool('tour_complete') == true && mounted) {
        setState(() => _tourLocallyDone = true);
      }
    });
    _userStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    _chatStream = FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: uid)
        .limit(50)       // 🔒 cap: prevents unbounded read for power users
        .snapshots();
    // Handle notification tap: switch to the tab indicated by main.dart
    final pendingTab = PendingNotification.tabIndex;
    if (pendingTab != null) {
      _selectedIndex = pendingTab;
      PendingNotification.clear();
    }

    if (uid != null) {
      // Badge: bookings needing customer approval
      _bookingsCustSub = FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: uid)
          .where('status', isEqualTo: 'expert_completed')
          .limit(100)    // 🔒 badge never needs more than 100 actionable jobs
          .snapshots()
          .listen((s) { if (mounted) setState(() => _bookingsCustBadge = s.docs.length); });

      // Badge: bookings needing expert to mark as done
      _bookingsExpertSub = FirebaseFirestore.instance
          .collection('jobs')
          .where('expertId', isEqualTo: uid)
          .where('status', isEqualTo: 'paid_escrow')
          .limit(100)    // 🔒 badge never needs more than 100 actionable jobs
          .snapshots()
          .listen((s) { if (mounted) setState(() => _bookingsExpertBadge = s.docs.length); });
    }
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    _bookingsCustSub?.cancel();
    _bookingsExpertSub?.cancel();
    _opportunitiesSub?.cancel();
    super.dispose();
  }

  void _setOnlineStatus(bool isOnline, {bool showFeedback = false}) async {
    if (currentUser != null) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((e) => debugPrint("Status error: $e"));

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: isOnline ? const Color(0xFF22C55E) : Colors.grey[700],
          behavior: SnackBarBehavior.floating,
          // Push above the bottom nav bar (≈80dp) so it doesn't overlap it
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          content: Text(
            isOnline
                ? 'עברת למצב זמין — לקוחות יכולים לראות אותך ✅'
                : 'עברת למצב לא זמין 🔕',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setOnlineStatus(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = currentUser?.email == adminEmail;

    // ── ShowCaseWidget wraps the entire screen so that Showcase targets
    //    defined in SearchPage and the bottom nav are all in the same tree.
    return ShowCaseWidget(
      onFinish: AppTour.markComplete,
      builder: (scCtx) {
        _showcaseCtx = scCtx;
        return _buildBody(context, isAdmin);
      },
    );
  }

  Widget _buildBody(BuildContext context, bool isAdmin) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Scaffold(body: Center(child: Text("שגיאה בטעינת הפרופיל")));
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        bool isBanned = data['isBanned'] ?? false;
        if (isBanned && !isAdmin) return _buildBannedScreen();

        bool isOnline = data['isOnline'] ?? false;

        // QA: סידור רשימת הדפים לפי סדר הלשוניות החדש
        void goToSearch() => setState(() => _selectedIndex = 0);

        bool isProvider = data['isProvider'] ?? false;
        String serviceType = (data['serviceType'] ?? '') as String;
        String userName = (data['name'] ?? '') as String;

        // ── Tour trigger ─────────────────────────────────────────────────────
        // Start once, after the frame builds, using the ShowCaseWidget context.
        // _tourLocallyDone is set from SharedPreferences in initState and acts
        // as an instant gate before the Firestore value arrives.
        final tourDone = _tourLocallyDone || (data['tourComplete'] as bool?) == true;
        if (!tourDone && !_tourStarted && _showcaseCtx != null) {
          _tourStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _showcaseCtx == null) return;
            if (isProvider) {
              AppTour.startProvider(_showcaseCtx!);
            } else {
              AppTour.startClient(_showcaseCtx!);
            }
          });
        }

        // Setup opportunities badge whenever serviceType or lastViewed timestamp changes
        final lastViewed = data['lastViewedOpportunitiesAt'] as Timestamp?;
        if (isProvider && (serviceType != _oppServiceType || lastViewed != _oppLastViewed)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setupOpportunitiesBadge(serviceType, lastViewed);
          });
        }

        // ── STABLE tab index map (never changes regardless of role) ─────────────
        // Index 0: חיפוש        — all users
        // Index 1: הזמנות        — all users
        // Index 2: צ'אט          — all users
        // Index 3: ארנק          — all users  (no _nestedTab — plain Scaffold)
        // Index 4: פרופיל        — all users
        // Index 5: הזדמנויות    — providers only  (added iff isProvider)
        // Index 6: ניהול         — admins only     (added iff isAdmin)
        // Index 7: מערכת         — admins only     (added iff isAdmin)
        //
        // Each _nestedTab(idx, …) uses _tabNavKeys[idx] as GlobalKey.
        // Because the keys are FIXED to the logical index, Flutter never
        // confuses AdminScreen with OpportunitiesScreen even when roles
        // arrive asynchronously from Firestore.
        // Profile tab position: 4 (not in bottom nav — accessed via header avatar).
        // Wallet restored to position 3 (key 3) so the bottom nav has:
        //   Home(0), Bookings(1), [QR center], Chat(2), Wallet(3).
        final int profileTabPos = 4;

        final List<Widget> tabs = [
          _nestedTab(0, HomeTab(
            userData: data,
            currentUserId: currentUser?.uid ?? '',
            isOnline: isOnline,
            onToggleOnline: (v) => _setOnlineStatus(v, showFeedback: true),
            onGoToBookings: () => setState(() => _selectedIndex = 1),
            onGoToChat: () => setState(() => _selectedIndex = 2),
            onOpenQuickRequest: () => _showQuickRequestSheet(context, data),
            onGoToProfile: () => setState(() => _selectedIndex = profileTabPos),
          )),
          _nestedTab(1, MyBookingsScreen(onGoToSearch: goToSearch)),
          _nestedTab(2, ChatListScreen(onGoToSearch: goToSearch)),
          _nestedTab(3, const FinanceScreen()),   // pos 3 / key 3 — Wallet
          _nestedTab(4, const ProfileScreen()),   // pos 4 / key 4 — Profile (avatar only)
        ];

        // Index 5 — Opportunities (providers only)
        if (isProvider) {
          tabs.add(_nestedTab(5, OpportunitiesScreen(
            key: ValueKey(serviceType),
            serviceType: serviceType,
            providerName: userName,
            isAdmin: isAdmin,
          )));
        }

        // Admin-only tabs.
        // Strict isAdmin guard: these tabs are NEVER added to the list for
        // non-admin users, so there is no possible list index that maps to
        // AdminScreen or SystemWalletScreen for a regular user.
        if (isAdmin) {
          tabs.add(_nestedTab(6, const AdminScreen()));
          tabs.add(_nestedTab(7, const SystemWalletScreen()));
        }

        // ── Guard: clamp _selectedIndex to valid range ────────────────────────
        // If the user's role changed (e.g. provider → customer removes יומן/הזדמנויות),
        // _selectedIndex may now exceed tabs.length - 1.
        // Schedule a reset so the next frame renders at index 0.
        final int safeIndex = _selectedIndex.clamp(0, tabs.length - 1);
        if (safeIndex != _selectedIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedIndex = 0);
          });
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, dynamic _) {
            if (didPop) return;
            final keyIdx = _tabKeyForPos(safeIndex, isProvider);
            final navState = _tabNavKeys[keyIdx].currentState;
            if (navState != null && navState.canPop()) {
              navState.pop();
            } else if (safeIndex != 0) {
              setState(() => _selectedIndex = 0);
            }
          },
          child: Scaffold(
          body: AnimatedOpacity(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            opacity: _tabFadeOpacity,
            child: IndexedStack(index: safeIndex, children: tabs),
          ),
          bottomNavigationBar: _buildEliteBottomNav(isAdmin, isProvider, serviceType, safeIndex, data),
          // ── Wolt-style floating "Urgent Search" button ────────────────
          // AnimatedScale + AnimatedOpacity give a smooth shrink-fade when
          // switching tabs. IgnorePointer blocks hit-tests while invisible so
          // the hidden button can never be accidentally tapped.
          floatingActionButton: AnimatedScale(
            scale: safeIndex == 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: safeIndex == 0 ? Curves.easeOutBack : Curves.easeIn,
            child: AnimatedOpacity(
              opacity: safeIndex == 0 ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: safeIndex != 0,
                child: FloatingActionButton.extended(
                  onPressed: () => _showQuickRequestSheet(context, data),
                  label: const Text(
                    'חיפוש דחוף',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.2,
                    ),
                  ),
                  // Magnifying glass with a bolt inside the lens — stacked Material icons.
                  icon: SizedBox(
                    width: 20,
                    height: 20,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: const [
                        Icon(Icons.search_rounded, color: Colors.white, size: 19),
                        Positioned(
                          top: 1,
                          left: 1,
                          child: Icon(Icons.bolt, color: Colors.white, size: 8),
                        ),
                      ],
                    ),
                  ),
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  extendedPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          ),         // close Scaffold
        );           // close PopScope
      },
    );
  }

  /// Wraps [child] in a tab-specific Navigator so sub-page pushes stay inside
  /// the tab without hiding the bottom nav.
  Navigator _nestedTab(int idx, Widget child) => Navigator(
    key: _tabNavKeys[idx],
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
  );

  /// Maps a list position (safeIndex) to the correct _tabNavKeys index.
  ///
  /// Tab list layout — positions and keys are 1:1 for 0–5:
  ///   pos 0 → key 0 (Home)
  ///   pos 1 → key 1 (Bookings)
  ///   pos 2 → key 2 (Chat)
  ///   pos 3 → key 3 (Wallet)
  ///   pos 4 → key 4 (Profile — not in nav bar, reached via header avatar)
  ///   pos 5 → key 5 (Opportunities, provider only)
  ///   pos 6 → key 6 (Admin)  / key 6 even without Opp (non-provider admin)
  ///   pos 7 → key 7 (System) / key 7 even without Opp
  ///
  /// Without a provider tab the list is shorter, so non-provider admins have:
  ///   pos 5 → key 6 (Admin), pos 6 → key 7 (System)
  int _tabKeyForPos(int pos, bool isProvider) {
    if (pos <= 4) return pos;                // 0–4: perfect 1:1
    if (isProvider) return pos;              // 5=Opp, 6=Admin, 7=System
    return pos + 1;                          // no Opp: pos5→key6(Admin), pos6→key7(System)
  }

  /// (Re)builds the opportunities badge stream when serviceType or lastViewed changes.
  void _setupOpportunitiesBadge(String serviceType, Timestamp? lastViewed) {
    _oppServiceType = serviceType;
    _oppLastViewed  = lastViewed;
    _opportunitiesSub?.cancel();

    if (serviceType.isEmpty) {
      if (mounted) setState(() => _opportunitiesBadge = 0);
      return;
    }

    var query = FirebaseFirestore.instance
        .collection('job_requests')
        .where('status', isEqualTo: 'open')
        .where('category', isEqualTo: serviceType);

    if (lastViewed != null) {
      query = query.where('createdAt', isGreaterThan: lastViewed);
    }

    _opportunitiesSub = query.snapshots().listen((s) {
      if (mounted) setState(() => _opportunitiesBadge = s.docs.length);
    });
  }

  /// Called when provider enters the Opportunities tab — resets badge and
  /// persists the "last viewed" timestamp to Firestore.
  Future<void> _markOpportunitiesSeen() async {
    if (_opportunitiesBadge == 0) return;
    setState(() => _opportunitiesBadge = 0);
    final uid = currentUser?.uid;
    if (uid == null) return;
    final now = Timestamp.now();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'lastViewedOpportunitiesAt': now});
    _setupOpportunitiesBadge(_oppServiceType, now);
  }

  Widget _buildEliteBottomNav(
    bool isAdmin,
    bool isProvider,
    String serviceType,
    int safeIndex,
    Map<String, dynamic> userData,
  ) {
    // שאילתת chat docs (קטנות) במקום collectionGroup על כל ההודעות
    return StreamBuilder<QuerySnapshot>(
      stream: _chatStream,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        int unreadCount = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            unreadCount += ((d['unreadCount_${currentUser?.uid}'] ?? 0) as num).toInt();
          }
        }

        // Tab list positions:
        //   0=Home, 1=Bookings, 2=Chat, 3=Wallet, 4=Profile(avatar only)
        //   5=Opp (provider), 6=Admin, 7=System (or 5=Admin,6=System without Opp)
        final int oppTabPos   = isProvider ? 5 : -1;
        final int adminTabPos = isProvider ? 6 : 5;
        final int sysTabPos   = isProvider ? 7 : 6;

        void onNavTap(int pos) {
          setState(() {
            _selectedIndex = pos;
            if (pos == 1) _bookingsLastCleared = _bookingsBadge;
            _tabFadeOpacity = 0.0;
          });
          Future.delayed(const Duration(milliseconds: 40), () {
            if (mounted) setState(() => _tabFadeOpacity = 1.0);
          });
          if (isProvider && pos == oppTabPos) _markOpportunitiesSeen();
        }

        final double bottomPad = MediaQuery.of(context).padding.bottom;

        // ── Flat inline nav bar — FAB is in the Row at the same height ──
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 66 + bottomPad,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                bottom: bottomPad,
                left: 4,
                right: 4,
              ),
              child: Row(
                children: [
                  // [Home] [Chat] [תמצא לי ●] [Bookings] [Wallet] ...
                  _navItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: l10n.tabHome,
                    index: 0,
                    currentIndex: safeIndex,
                    onTap: () => onNavTap(0),
                  ),
                  _navItem(
                    icon: Icons.chat_bubble_outline,
                    activeIcon: Icons.chat_bubble,
                    label: l10n.tabChat,
                    index: 2,
                    currentIndex: safeIndex,
                    onTap: () => onNavTap(2),
                    badge: unreadCount,
                  ),

                  _navItem(
                    icon: Icons.receipt_long_outlined,
                    activeIcon: Icons.receipt_long,
                    label: l10n.tabBookings,
                    index: 1,
                    currentIndex: safeIndex,
                    onTap: () => onNavTap(1),
                    badge: _bookingsVisibleBadge,
                  ),
                  _navItem(
                    icon: Icons.account_balance_wallet_outlined,
                    activeIcon: Icons.account_balance_wallet,
                    label: l10n.tabWallet,
                    index: 3,
                    currentIndex: safeIndex,
                    onTap: () => onNavTap(3),
                    tourKey: tourProviderWalletKey,
                    tourTitle: 'ארנק שלי 💰',
                    tourDesc:
                        'כאן תראה את יתרתך, תוכל למשוך לחשבון בנק ולעקוב אחר כל תשלום',
                  ),
                  // Opportunities (providers)
                  if (isProvider)
                    _navItem(
                      icon: Icons.work_outline_rounded,
                      activeIcon: Icons.work_rounded,
                      label: 'הזדמנויות',
                      index: oppTabPos,
                      currentIndex: safeIndex,
                      onTap: () => onNavTap(oppTabPos),
                      badge: _opportunitiesBadge,
                      tourKey: tourProviderOppKey,
                      tourTitle: 'הזדמנויות 🚀',
                      tourDesc:
                          'לקוחות מחפשים ספקים בתחומך — ראו בקשות חדשות ומצאו הזמנות',
                    ),
                  // Admin & System tabs
                  if (isAdmin) ...[
                    _navItem(
                      icon: Icons.admin_panel_settings_outlined,
                      activeIcon: Icons.admin_panel_settings,
                      label: 'ניהול',
                      index: adminTabPos,
                      currentIndex: safeIndex,
                      onTap: () => onNavTap(adminTabPos),
                    ),
                    _navItem(
                      icon: Icons.analytics_outlined,
                      activeIcon: Icons.analytics,
                      label: 'מערכת',
                      index: sysTabPos,
                      currentIndex: safeIndex,
                      onTap: () => onNavTap(sysTabPos),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Single nav item for the custom bottom bar.
  Widget _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required int currentIndex,
    required VoidCallback onTap,
    int badge = 0,
    GlobalKey? tourKey,
    String? tourTitle,
    String? tourDesc,
  }) {
    final bool active = currentIndex == index;
    final color = active ? Colors.black : Colors.grey[400]!;

    Widget iconWidget = Icon(active ? activeIcon : icon, color: color, size: 24);
    if (badge > 0) {
      iconWidget = Badge(
        label: Text(badge.toString()),
        isLabelVisible: true,
        child: iconWidget,
      );
    }
    if (tourKey != null && tourTitle != null && tourDesc != null) {
      iconWidget = AnyShowcase(
        tourKey: tourKey,
        title: tourTitle,
        description: tourDesc,
        tooltipPosition: TooltipPosition.top,
        child: iconWidget,
      );
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickRequestSheet(BuildContext context, Map<String, dynamic> userData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickRequestSheet(
        clientUid: currentUser?.uid ?? '',
        clientName: (userData['name'] ?? 'לקוח') as String,
      ),
    );
  }

  Widget _buildBannedScreen() {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.gpp_bad_outlined, color: Colors.redAccent, size: 100), const SizedBox(height: 20), const Text("החשבון הושעה", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 40), ElevatedButton(onPressed: () => performSignOut(context), child: const Text("התנתקות"))])));
  }
}

// ─── Quick Request Sheet (with AI Matchmaker Agent) ───────────────────────────

enum _SheetPhase { input, thinking, result }

class _QuickRequestSheet extends StatefulWidget {
  final String clientUid;
  final String clientName;

  const _QuickRequestSheet(
      {required this.clientUid, required this.clientName});

  @override
  State<_QuickRequestSheet> createState() => _QuickRequestSheetState();
}

class _QuickRequestSheetState extends State<_QuickRequestSheet> {
  final _descCtrl = TextEditingController();
  final _locCtrl  = TextEditingController();

  RequestAnalysis  _analysis          = const RequestAnalysis();
  _SheetPhase      _phase             = _SheetPhase.input;
  MatchmakerResult? _matchResult;
  String?          _confirmedCategory;
  int              _activeRequestCount = 0;

  // Animated dots for thinking phase
  int    _dotCount  = 1;
  Timer? _dotsTimer;

  @override
  void initState() {
    super.initState();
    _descCtrl.addListener(_onTextChanged);
    _loadActiveRequestCount();
  }

  @override
  void dispose() {
    _descCtrl.removeListener(_onTextChanged);
    _descCtrl.dispose();
    _locCtrl.dispose();
    _dotsTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final analysis = AiAnalysisService.analyze(_descCtrl.text);
    if (mounted) setState(() => _analysis = analysis);
  }

  Future<void> _loadActiveRequestCount() async {
    if (widget.clientUid.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('job_requests')
        .where('clientId', isEqualTo: widget.clientUid)
        .where('status', isEqualTo: 'open')
        .limit(10)
        .get();
    if (mounted) setState(() => _activeRequestCount = snap.docs.length);
  }

  void _startDotsTimer() {
    _dotsTimer?.cancel();
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (mounted) setState(() => _dotCount = (_dotCount % 3) + 1);
    });
  }

  // ── Main broadcast + matchmaker flow ──────────────────────────────────────
  Future<void> _broadcast() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('נא לתאר את הבקשה'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // Transition to thinking phase
    setState(() => _phase = _SheetPhase.thinking);
    _startDotsTimer();

    // Capture l10n-safe values before any await
    // resolveCanonicalCategory maps AI-suggested names (e.g. 'כושר ואימון')
    // and user variants ('מאמן כושר') to the APP_CATEGORIES canonical name
    // ('אימון כושר') that Sigalit's Opportunities query filters on.
    final category   = resolveCanonicalCategory(
        _confirmedCategory ?? (_analysis.suggestedCategory ?? ''));
    final isUrgent   = _analysis.urgency == 'urgent';
    final locText    = _locCtrl.text.trim();

    try {
      // Get location + urgency fee in parallel
      final results = await Future.wait([
        LocationService.getIfGranted(),
        if (isUrgent)
          CacheService.getDoc('admin/admin/settings', 'settings',
              ttl: CacheService.kAdminSettings)
        else
          Future.value(null),
      ]);

      final pos          = results[0] as dynamic;
      final settingsData = isUrgent ? results[1] as Map<String, dynamic>? : null;
      final urgencyFeePct = isUrgent
          ? (((settingsData?['urgencyFeePercentage'] as num?) ?? 0.05) * 100).toDouble()
          : 0.0;

      // Write job_request and call matchmakerpitch in parallel
      final futures = await Future.wait([
        FirebaseFirestore.instance.collection('job_requests').add({
          'clientId':               widget.clientUid,
          'clientName':             widget.clientName,
          'description':            desc,
          'location':               locText,
          'category':               category,
          'status':                 'open',
          'urgency':                _analysis.urgency,
          if (isUrgent) 'urgencyFeePercentage': urgencyFeePct,
          if (isUrgent) 'surgeMultiplier': 1.2,
          'interestedProviders':    [],
          'interestedProviderNames': [],
          'interestedCount':        0,
          'createdAt':              FieldValue.serverTimestamp(),
          if (pos != null) 'clientLat': (pos as dynamic).latitude as double,
          if (pos != null) 'clientLng': (pos as dynamic).longitude as double,
        }),
        MatchmakerService.findMatch(
          requestText: desc,
          category:    category,
          clientName:  widget.clientName,
          clientLat:   pos != null ? (pos as dynamic).latitude as double? : null,
          clientLng:   pos != null ? (pos as dynamic).longitude as double? : null,
        ),
      ]);

      final matchResult = futures[1] as MatchmakerResult?;
      _dotsTimer?.cancel();

      if (!mounted) return;

      if (matchResult != null && matchResult.pitch.isNotEmpty) {
        // 🔒 Solution Snap — the AI locked in a match
        AudioService.instance.play(AppSound.solutionSnap);
        // Show AI result
        setState(() {
          _matchResult = matchResult;
          _phase       = _SheetPhase.result;
        });
      } else {
        // No match found — fall back to plain snackbar
        Navigator.pop(context);
        final msg = isUrgent
            ? 'הבקשה הדחופה פורסמה! מחיר x1.2 (surge) • תוספת דחיפות ${urgencyFeePct.toStringAsFixed(0)}% 🔥'
            : 'הבקשה פורסמה! ספקים יפנו אליך בקרוב 🚀';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: isUrgent ? const Color(0xFFEA580C) : Colors.green,
          content: Text(msg),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      _dotsTimer?.cancel();
      if (mounted) {
        // Revert to input phase so user can try again
        setState(() => _phase = _SheetPhase.input);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('שגיאה: $e')),
        );
      }
    }
  }

  // ── Broadcast to all (after seeing result) ────────────────────────────────
  void _broadcastAll() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      backgroundColor: Colors.green,
      content: Text('הבקשה פורסמה לכל הספקים! 🚀'),
      duration: Duration(seconds: 3),
    ));
  }

  // ── Open chat with top match ──────────────────────────────────────────────
  void _openMatchChat(MatchedProvider provider) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          receiverId:       provider.uid,
          receiverName:     provider.name,
          currentUserName:  widget.clientName,
          initialMessage:   _descCtrl.text.trim(),
        ),
      ),
    );
  }

  // ── Shared sheet wrapper ──────────────────────────────────────────────────
  Widget _sheetWrap(Widget child) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: SingleChildScrollView(child: child),
    ),
  );

  Widget _dragHandle() => Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _SheetPhase.input    => _buildInputPhase(),
      _SheetPhase.thinking => _buildThinkingPhase(),
      _SheetPhase.result   => _buildResultPhase(_matchResult!),
    };
  }

  // ── Phase 1: Input ────────────────────────────────────────────────────────
  Widget _buildInputPhase() => _sheetWrap(Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _dragHandle(),
      const SizedBox(height: 16),

      // Active requests banner
      if (_activeRequestCount > 0)
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyRequestsScreen()));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFF0F0FF), Color(0xFFE8E8FF)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Color(0xFF6366F1)),
              const Spacer(),
              Text('יש לך $_activeRequestCount בקשות פעילות',
                  style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(width: 6),
              const Icon(Icons.campaign_rounded,
                  size: 16, color: Color(0xFF6366F1)),
            ]),
          ),
        ),

      // Sheet header
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('פרסם בקשה מהירה',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('תאר מה אתה צריך — AI ימצא לך את המתאים',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 22),
        ),
      ]),
      const SizedBox(height: 20),

      // Description field
      Container(
        decoration: BoxDecoration(
            color: const Color(0xFFF5F6FA),
            borderRadius: BorderRadius.circular(16)),
        child: TextField(
          controller: _descCtrl,
          maxLines: 4,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            hintText:
                'תאר מה אתה צריך...\nלמשל: "צריך שרברב מחר ב-10:00 לתיקון ברז דולף"',
            hintStyle:
                TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(16),
          ),
        ),
      ),

      // ── AI analysis panel ──────────────────────────────────────
      AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                child: _analysis.hasInsights
                    ? _buildAiInsights()
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 12),

              // Location field
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _locCtrl,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    hintText: 'אזור כללי (אופציונלי) — למשל: תל אביב',
                    hintStyle:
                        TextStyle(color: Colors.grey, fontSize: 13),
                    prefixIcon: Icon(Icons.location_on_outlined,
                        color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // AI Matchmaker CTA
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 58),
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _broadcast,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('חיפוש מהיר ✨',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ));

  // ── Phase 2: Thinking ─────────────────────────────────────────────────────
  Widget _buildThinkingPhase() => _sheetWrap(Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _dragHandle(),
      const SizedBox(height: 32),

      // AI avatar + pulsing ring
      Center(
        child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.40),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 32),
        ),
      ),
      const SizedBox(height: 20),

      const Text(
        'AI Matchmaker',
        style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold,
          color: Color(0xFF1E1B4B),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'מחפש את הספק המתאים ביותר${'●' * _dotCount}',
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 32),
    ],
  ));

  // ── Phase 3: Result ───────────────────────────────────────────────────────
  Widget _buildResultPhase(MatchmakerResult result) {
    final provider = result.topProvider;
    return _sheetWrap(Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dragHandle(),
        const SizedBox(height: 20),

        // ── AI Agent header ────────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('AI Matchmaker',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1B4B))),
            SizedBox(height: 2),
            Text('מצאתי התאמה בשבילך',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 22),
          ),
        ]),
        const SizedBox(height: 20),

        // ── AI chat bubble (pitch) ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0FF),
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(18),
              bottomLeft:  Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.18)),
          ),
          child: Text(
            result.pitch,
            style: const TextStyle(
                fontSize: 14, height: 1.6, color: Color(0xFF1E1B4B)),
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
          ),
        ),

        // ── Top provider card ─────────────────────────────────────────────
        if (provider != null) ...[
          const SizedBox(height: 16),
          _buildProviderCard(provider),
        ],
        const SizedBox(height: 20),

        // ── CTAs ──────────────────────────────────────────────────────────
        if (provider != null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: () => _openMatchChat(provider),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('שלח בקשה ל${provider.name}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _broadcastAll,
          child: Text(
            'שדר לכל הספקים במקום',
            style: TextStyle(
                color: Colors.grey[500], fontSize: 13),
          ),
        ),
      ],
    ));
  }

  Widget _buildProviderCard(MatchedProvider provider) {
    final stars = provider.rating.clamp(0.0, 5.0);
    final distStr = provider.distKm != null
        ? '${provider.distKm!.toStringAsFixed(1)} ק"מ'
        : null;
    final priceStr = provider.pricePerHour > 0
        ? '₪${provider.pricePerHour.toStringAsFixed(0)}/שעה'
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Action arrow (RTL: on left)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Color(0xFF059669)),
          ),
          const Spacer(),
          // Info column
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(children: [
              if (provider.isOnline)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('מחובר',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              Text(provider.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              for (int i = 0; i < 5; i++)
                Icon(
                  i < stars.floor()
                      ? Icons.star_rounded
                      : (i < stars ? Icons.star_half_rounded : Icons.star_border_rounded),
                  color: const Color(0xFFFBBF24),
                  size: 14,
                ),
              const SizedBox(width: 4),
              Text(stars.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (priceStr != null) ...[
                Text(priceStr,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF059669),
                        fontWeight: FontWeight.w600)),
                if (distStr != null) const Text(' · ',
                    style: TextStyle(color: Colors.grey)),
              ],
              if (distStr != null)
                Row(children: [
                  const Icon(Icons.location_on_rounded,
                      size: 12, color: Colors.grey),
                  Text(distStr,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ]),
            ]),
          ]),
          const SizedBox(width: 14),
          // Avatar
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
            backgroundImage: provider.profileImage.isNotEmpty
                ? NetworkImage(provider.profileImage)
                : null,
            child: provider.profileImage.isEmpty
                ? Text(
                    provider.name.isNotEmpty ? provider.name[0] : '?',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1)),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAiInsights() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Category suggestion
          if (_analysis.suggestedCategory != null)
            _aiChip(
              icon: '🏷️',
              label: 'נראה שמדובר ב: ${_analysis.suggestedCategory}',
              color: const Color(0xFF6366F1),
              bg: const Color(0xFFF0F0FF),
              onConfirm: () => setState(
                  () => _confirmedCategory = _analysis.suggestedCategory),
              confirmed: _confirmedCategory == _analysis.suggestedCategory,
            ),

          // Urgency signal
          if (_analysis.urgency == 'urgent') ...[
            const SizedBox(height: 6),
            _aiChip(
              icon: '🔥',
              label: 'דחוף — ספקים זמינים יקבלו עדיפות',
              color: const Color(0xFFEA580C),
              bg: const Color(0xFFFFF7ED),
            ),
          ],

          // Smart prompts for missing info
          if (_analysis.missingDate) ...[
            const SizedBox(height: 6),
            _suggestionChip(
              icon: '📅',
              label: 'מתי תרצה את השירות?',
              onTap: () {
                _descCtrl.text = '${_descCtrl.text.trimRight()} מחר בבוקר';
                _descCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _descCtrl.text.length));
              },
            ),
          ],
          if (_analysis.missingLocation) ...[
            const SizedBox(height: 6),
            _suggestionChip(
              icon: '📍',
              label: 'באיזה אזור?',
              onTap: () {
                _locCtrl.text = '';
                FocusScope.of(context).requestFocus(FocusNode());
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _aiChip({
    required String icon,
    required String label,
    required Color color,
    required Color bg,
    VoidCallback? onConfirm,
    bool confirmed = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onConfirm != null && !confirmed)
            GestureDetector(
              onTap: onConfirm,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('✓ אמת',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          if (confirmed)
            const Icon(Icons.check_circle_rounded,
                size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Text(icon, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _suggestionChip({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber[600],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('+ הוסף',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: Colors.amber[800],
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Text(icon, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}