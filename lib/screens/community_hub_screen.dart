import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:intl/intl.dart';

import '../services/community_hub_service.dart';
import '../services/location_service.dart';
import '../utils/image_compressor.dart';
import '../utils/safe_image_provider.dart';
import 'chat_screen.dart';
import 'phone_login_screen.dart';

// ── Colors ───────────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF10B981);
const _kIndigo = Color(0xFF6366F1);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kDark = Color(0xFF1A1A2E);
const _kMuted = Color(0xFF6B7280);
const _kBg = Color(0xFFFFF8F5); // warm cream
const _kCardBg = Colors.white;

class CommunityHubScreen extends StatefulWidget {
  const CommunityHubScreen({super.key});

  @override
  State<CommunityHubScreen> createState() => _CommunityHubScreenState();
}

class _CommunityHubScreenState extends State<CommunityHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // User state
  bool _isVolunteer = false;
  String _userName = '';
  String? _userImage;
  bool _userLoading = true;

  // Give Help tab
  String? _selectedTypeFilter;
  bool _showMap = false;

  // Request Help form
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedCategory = 'other';
  String _selectedRequesterType = 'general';
  String _selectedUrgency = 'low';
  bool _isAnonymous = false;
  bool _submitting = false;
  DateTime? _targetDate;

  // Celebration overlay
  bool _showCelebration = false;
  int _celebrationXp = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {}); // rebuild for FAB visibility on swipe
    });
    _loadUserData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _userLoading = false);
      return;
    }
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!mounted) return;
      final data = doc.data() ?? {};
      setState(() {
        _isVolunteer = data['isVolunteer'] == true;
        _userName = (data['name'] as String?) ?? '';
        _userImage = data['profileImage'] as String?;
        _userLoading = false;
      });
    } catch (e) {
      debugPrint('[CommunityHub] loadUserData error: $e');
      if (mounted) setState(() => _userLoading = false);
    }
  }

  // ── Join / Leave Volunteer ─────────────────────────────────────────────────

  Future<void> _toggleVolunteer() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }

    // If joining, show info modal first
    if (!_isVolunteer) {
      final proceed = await _showJoinModal();
      if (!proceed) return;
    }

    try {
      final newVal = !_isVolunteer;
      await _db.collection('users').doc(user.uid).update({
        'isVolunteer': newVal,
      });
      if (!mounted) return;
      setState(() => _isVolunteer = newVal);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVal ? '🎉 הצטרפת לקהילת המתנדבים!' : 'יצאת מתוכנית ההתנדבות',
          ),
          backgroundColor: newVal ? _kGreen : _kMuted,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאה: $e')));
      }
    }
  }

  Future<bool> _showJoinModal() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Heart icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kRed, Color(0xFFEC4899)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: _kRed.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'הצטרף/י לקהילת המתנדבים',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'כישרון אחד, לב אחד',
                  style: TextStyle(
                    fontSize: 15,
                    color: _kMuted,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Benefits
                _benefitTile(
                  Icons.star_rounded,
                  _kAmber,
                  '+${CommunityHubService.communityXpReward} XP לכל התנדבות',
                  'פי 3 מהרגיל — עלה בדרגה מהר יותר!',
                ),
                const SizedBox(height: 14),
                _benefitTile(
                  Icons.favorite_rounded,
                  _kRed,
                  'לב אדום בפרופיל שלך',
                  'מראה לכולם שאתה חלק מהקהילה.',
                ),
                const SizedBox(height: 14),
                _benefitTile(
                  Icons.auto_awesome_rounded,
                  _kIndigo,
                  'תגי הישג: מתחיל → עמוד תווך → מלאך',
                  'אספו תגים וגדלו בקהילה.',
                ),
                const SizedBox(height: 14),
                _benefitTile(
                  Icons.trending_up_rounded,
                  _kGreen,
                  'עדיפות בתוצאות חיפוש',
                  'מתנדבים מקבלים דחיפה בדירוג.',
                ),

                const SizedBox(height: 28),

                // CTA
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'אני רוצה להתנדב!',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'אולי אחר כך',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
    );
    return result ?? false;
  }

  Widget _benefitTile(IconData icon, Color color, String title, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 12,
                  color: _kMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ],
    );
  }

  // ── Claim Request ──────────────────────────────────────────────────────────

  Future<void> _claimRequest(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }

    if (!_isVolunteer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('עליך להצטרף כמתנדב/ת לפני שתוכל/י לעזור'),
          backgroundColor: _kAmber,
        ),
      );
      return;
    }

    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';
    final requesterName = data['requesterName'] as String? ?? 'אנונימי';

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('אישור התנדבות'),
            content: Text(
              'האם ברצונך לעזור ב"$title"?\n\n'
              'לאחר האישור ייפתח צ\'אט עם $requesterName לתיאום.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('אני רוצה לעזור!'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    final error = await CommunityHubService.claimRequest(
      requestId: doc.id,
      volunteerId: user.uid,
      volunteerName: _userName.isNotEmpty ? _userName : 'מתנדב/ת',
    );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _kRed));
      return;
    }

    // Success — open chat with requester
    final requesterId = data['requesterId'] as String? ?? '';
    if (requesterId.isNotEmpty) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder:
              (_) => ChatScreen(
                receiverId: requesterId,
                receiverName: requesterName,
                initialMessage:
                    '🤝 שלום! אישרתי את בקשת ההתנדבות שלך — "$title". '
                    'נתאם פרטים?',
              ),
        ),
      );
    }
  }

  // ── Submit New Request ─────────────────────────────────────────────────────

  Future<void> _submitRequest() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא להזין כותרת (לפחות 3 תווים)')),
      );
      return;
    }
    if (desc.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לתאר את הבקשה (לפחות 10 תווים)')),
      );
      return;
    }

    setState(() => _submitting = true);

    // Get user location if available
    GeoPoint? location;
    final cached = LocationService.cached;
    if (cached != null) {
      location = GeoPoint(cached.latitude, cached.longitude);
    }

    final successMsg = 'הבקשה נשלחה בהצלחה!';
    final id = await CommunityHubService.createRequest(
      requesterId: user.uid,
      requesterName: _userName,
      title: title,
      description: desc,
      category: _selectedCategory,
      requesterType: _selectedRequesterType,
      urgency: _selectedUrgency,
      isAnonymous: _isAnonymous,
      location: location,
      requesterImage: _userImage,
      targetDate: _targetDate,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (id != null) {
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _isAnonymous = false;
        _selectedUrgency = 'low';
        _targetDate = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שגיאה בשליחת הבקשה. נסה שוב.'),
          backgroundColor: _kRed,
        ),
      );
    }
  }

  // ── Confirm Completion ─────────────────────────────────────────────────────

  Future<void> _confirmCompletion(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final data = doc.data() as Map<String, dynamic>? ?? {};
    final volunteerName = data['volunteerName'] as String? ?? 'מתנדב/ת';

    String reviewText = '';
    String thankYouNote = '';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final canConfirm =
                reviewText.trim().length >= CommunityHubService.minReviewLength;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: _kCardBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _kGreen,
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'אישור ותודה',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _kDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$volunteerName עזר/ה לך? ספר/י לנו קצת!',
                        style: const TextStyle(fontSize: 14, color: _kMuted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Review field
                      TextField(
                        maxLines: 3,
                        textAlign: TextAlign.start,
                        decoration: InputDecoration(
                          hintText: 'ספר/י על חוויית ההתנדבות (לפחות 10 תווים)',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: _kGreen,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                          counterText: '${reviewText.trim().length}/10',
                        ),
                        onChanged: (v) => setSheetState(() => reviewText = v),
                      ),
                      const SizedBox(height: 16),

                      // Thank You Note field
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Row(
                          children: [
                            Icon(
                              Icons.favorite_rounded,
                              size: 16,
                              color: _kRed,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'כתוב/י תודה קצרה (יופיע בפרופיל המתנדב)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        maxLines: 2,
                        textAlign: TextAlign.start,
                        decoration: InputDecoration(
                          hintText: 'תודה רבה על העזרה! (לא חובה)',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: _kRed,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                        onChanged: (v) => setSheetState(() => thankYouNote = v),
                      ),
                      const SizedBox(height: 14),

                      // XP reward preview
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _kAmber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: _kAmber,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'המתנדב/ת יקבל/ת +${CommunityHubService.communityXpReward} XP',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed:
                              canConfirm
                                  ? () => Navigator.pop(ctx, true)
                                  : null,
                          icon: const Icon(Icons.favorite_rounded, size: 20),
                          label: const Text(
                            'אשר ותודה',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[300],
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    String result;
    try {
      debugPrint('[CommunityHub] calling completeRequest for doc=${doc.id}, '
          'uid=${user.uid}');
      result = await CommunityHubService.completeRequest(
        requestId: doc.id,
        confirmingUserId: user.uid,
        reviewText: reviewText,
        thankYouNote: thankYouNote,
      );
      debugPrint('[CommunityHub] completeRequest returned: $result');
    } catch (e, stack) {
      debugPrint('[CommunityHub] completeRequest threw (unexpected): $e');
      debugPrint('[CommunityHub] stack: $stack');
      result = 'שגיאה באישור הבקשה. נסה שוב.';
    }

    if (!mounted) return;

    if (result == 'ok' || result == 'ok_partial') {
      // ── Success: show celebration, card disappears via stream ──────
      setState(() {
        _showCelebration = true;
        _celebrationXp = CommunityHubService.communityXpReward;
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _showCelebration = false);
      });

      // If partial success, show a soft info snackbar (not red error)
      if (result == 'ok_partial') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הבקשה אושרה! תגמולי המתנדב/ת יעודכנו בקרוב.'),
            backgroundColor: Color(0xFFF59E0B),
          ),
        );
      }
    } else {
      debugPrint('[CommunityHub] completeRequest rejected: $result');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: _kRed),
      );
    }
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder:
          (c) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('עליך להיכנס לחשבון'),
            content: const Text(
              'כדי להשתמש בקהילת AnySkill עליך להיות מחובר/ת.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('סגור'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.of(context, rootNavigator: true).pushReplacement(
                    MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
                  );
                },
                child: const Text('היכנס'),
              ),
            ],
          ),
    );
  }

  void _showFullPhoto(BuildContext ctx, String url) {
    showDialog(
      context: ctx,
      builder:
          (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder:
                (context, innerBoxIsScrolled) => [
                  _buildHeroAppBar(),
                  _buildStickyTabBar(innerBoxIsScrolled),
                ],
            body: TabBarView(
              controller: _tabCtrl,
              children: [_buildGiveHelpTab(), _buildRequestHelpTab()],
            ),
          ),

          // Celebration overlay
          if (_showCelebration) _buildCelebrationOverlay(),
        ],
      ),
      floatingActionButton: _tabCtrl.index == 0 ? _buildMapFab() : null,
    );
  }

  // ── Hero AppBar ────────────────────────────────────────────────────────────

  SliverAppBar _buildHeroAppBar() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: _kRed,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AnySkill Community',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                shadows: [Shadow(blurRadius: 8, color: Colors.black38)],
              ),
            ),
            Text(
              'כישרון אחד, לב אחד',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFF8B5CF6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: Stack(
            children: [
              // Subtle pattern overlay
              Positioned.fill(
                child: Opacity(
                  opacity: 0.08,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                        ),
                    itemCount: 24,
                    itemBuilder:
                        (_, __) => const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                  ),
                ),
              ),
              // Center icon
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 50),
                  child: Icon(
                    Icons.volunteer_activism_rounded,
                    size: 72,
                    color: Colors.white24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sticky Tab Bar ─────────────────────────────────────────────────────────

  SliverPersistentHeader _buildStickyTabBar(bool innerBoxIsScrolled) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyTabBarDelegate(
        TabBar(
          controller: _tabCtrl,
          onTap: (_) => setState(() {}), // rebuild for FAB visibility
          labelColor: _kRed,
          unselectedLabelColor: _kMuted,
          indicatorColor: _kRed,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.volunteer_activism_rounded, size: 20),
              text: 'תן עזרה',
            ),
            Tab(
              icon: Icon(Icons.add_circle_outline_rounded, size: 20),
              text: 'בקש עזרה',
            ),
          ],
        ),
      ),
    );
  }

  // ── Map FAB ────────────────────────────────────────────────────────────────

  Widget _buildMapFab() {
    return FloatingActionButton(
      onPressed: () => setState(() => _showMap = !_showMap),
      backgroundColor: _showMap ? _kDark : _kIndigo,
      child: Icon(
        _showMap ? Icons.list_rounded : Icons.map_rounded,
        color: Colors.white,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB A — GIVE HELP
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildGiveHelpTab() {
    final uid = _auth.currentUser?.uid;
    return Column(
      children: [
        // Join banner (if not yet a volunteer)
        if (!_isVolunteer && !_userLoading) _buildJoinBanner(),

        // Active Tasks section (for volunteers with claimed tasks)
        if (_isVolunteer && uid != null) _buildActiveTasksSection(uid),

        // Filter chips
        _buildFilterChips(),

        // Content: map or list
        Expanded(child: _showMap ? _buildMapView() : _buildRequestsFeed()),
      ],
    );
  }

  // ── Active Tasks Section (Volunteer side) ─────────────────────────────────

  Widget _buildActiveTasksSection(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: CommunityHubService.streamMyVolunteerTasks(uid),
      builder: (context, snap) {
        if (snap.hasError || snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kIndigo.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment_rounded, color: _kIndigo, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'ההתנדבויות הפעילות שלי',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...docs.map((doc) => _buildActiveTaskCard(doc)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTaskCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    final requesterName = data['requesterName'] as String? ?? 'פונה';
    final requesterId = data['requesterId'] as String? ?? '';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'accepted':
        statusColor = _kAmber;
        statusText = 'ממתין לאישור הפונה';
        statusIcon = Icons.hourglass_top_rounded;
      case 'in_progress':
        statusColor = _kIndigo;
        statusText = 'בביצוע';
        statusIcon = Icons.handyman_rounded;
      case 'pending_confirmation':
        statusColor = const Color(0xFF8B5CF6);
        statusText = 'ממתין לאישור סיום';
        statusIcon = Icons.pending_actions_rounded;
      default:
        statusColor = _kMuted;
        statusText = status;
        statusIcon = Icons.info_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'עבור $requesterName',
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 10),

          // Actions based on status
          Row(
            children: [
              // "I Finished Helping!" button — only when in_progress
              if (status == 'in_progress')
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => _markTaskDone(doc),
                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                      label: const Text(
                        'סיימתי לעזור!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),

              // Chat button — always available
              if (status == 'in_progress') const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  if (requesterId.isNotEmpty) {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder:
                            (_) => ChatScreen(
                              receiverId: requesterId,
                              receiverName: requesterName,
                            ),
                      ),
                    );
                  }
                },
                icon: const Icon(
                  Icons.chat_bubble_rounded,
                  size: 20,
                  color: _kIndigo,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _markTaskDone(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';

    // ── Timing guard (client-side preview — server also enforces) ────────
    final startedAt = data['startedAt'] as Timestamp?;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt.toDate()).inMinutes;
      if (elapsed < CommunityHubService.minTaskDurationMinutes) {
        final remaining = CommunityHubService.minTaskDurationMinutes - elapsed;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'יש להמתין עוד $remaining דקות לפני סימון סיום '
              '(מינימום ${CommunityHubService.minTaskDurationMinutes} דקות)',
            ),
            backgroundColor: _kAmber,
          ),
        );
        return;
      }
    }

    // ── Photo evidence bottom sheet ─────────────────────────────────────
    CompressedImage? pickedPhoto;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: _kCardBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Icon(
                      Icons.camera_alt_rounded,
                      color: _kGreen,
                      size: 48,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'סיימתי לעזור!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'צלם/י תמונה של העבודה שבוצעה ב"$title"',
                      style: const TextStyle(fontSize: 14, color: _kMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Photo area
                    GestureDetector(
                      onTap: () async {
                        final img = await ImageCompressor.pick(
                          ImagePreset.chatImage,
                        );
                        if (img != null) {
                          setSheetState(() => pickedPhoto = img);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                pickedPhoto != null
                                    ? _kGreen
                                    : Colors.grey[300]!,
                            width: pickedPhoto != null ? 2 : 1,
                          ),
                        ),
                        child:
                            pickedPhoto != null
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Image.memory(
                                    pickedPhoto!.bytes,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_rounded,
                                      size: 40,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'לחץ/י כדי לצלם / לבחור תמונה',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Mandatory notice
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'תמונת הוכחה היא חובה — תוצג לפונה לאישור',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed:
                            pickedPhoto != null
                                ? () => Navigator.pop(ctx, true)
                                : null,
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text(
                          'שלח סיום + תמונה',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[300],
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || pickedPhoto == null) return;

    // ── Upload photo to Storage ─────────────────────────────────────────
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('מעלה תמונה...'),
        backgroundColor: _kIndigo,
        duration: Duration(seconds: 10),
      ),
    );

    String photoUrl;
    try {
      final storagePath =
          'community_evidence/${doc.id}_${DateTime.now().millisecondsSinceEpoch}.${pickedPhoto!.ext}';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(pickedPhoto!.bytes);
      photoUrl = await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[CommunityHub] photo upload error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שגיאה בהעלאת התמונה. נסה שוב.'),
          backgroundColor: _kRed,
        ),
      );
      return;
    }

    // ── Call service ─────────────────────────────────────────────────────
    final error = await CommunityHubService.markTaskDone(
      requestId: doc.id,
      volunteerId: user.uid,
      completionPhotoUrl: photoUrl,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _kRed));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הפונה יקבל התראה לאשר את הסיום'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildJoinBanner() {
    return GestureDetector(
      onTap: _toggleVolunteer,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEF4444), Color(0xFFEC4899)],
            begin: AlignmentDirectional.centerEnd,
            end: AlignmentDirectional.centerStart,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _kRed.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'הצטרף/י לקהילת המתנדבים',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'כל אחד יכול לעזור — לא צריך להיות נותן שירות!',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Icon(Icons.favorite_rounded, color: Colors.white, size: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _filterChip(null, 'הכל', Icons.apps_rounded),
          ...CommunityHubService.requesterTypes.map(
            (t) => _filterChip(
              t['id'] as String,
              t['label'] as String,
              CommunityHubService.requesterTypeIcon(t['id'] as String),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String? typeId, String label, IconData icon) {
    final isSelected = _selectedTypeFilter == typeId;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : _kMuted),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : _kDark,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        backgroundColor: _kCardBg,
        selectedColor: _kRed,
        checkmarkColor: Colors.white,
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? _kRed : Colors.grey[300]!),
        ),
        onSelected: (_) {
          setState(() {
            _selectedTypeFilter = isSelected ? null : typeId;
          });
        },
      ),
    );
  }

  // ── Requests Feed ──────────────────────────────────────────────────────────

  Widget _buildRequestsFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: CommunityHubService.streamOpenRequests(
        requesterType: _selectedTypeFilter,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('שגיאה בטעינת הבקשות'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kRed));
        }

        final docs = snap.data?.docs ?? [];
        final uid = _auth.currentUser?.uid;

        // Filter out user's own requests
        final filteredDocs =
            docs.where((d) {
              final data = d.data() as Map<String, dynamic>? ?? {};
              return data['requesterId'] != uid;
            }).toList();

        if (filteredDocs.isEmpty) {
          return _buildEmptyFeed();
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
          itemCount: filteredDocs.length,
          itemBuilder: (_, i) => _buildRequestCard(filteredDocs[i]),
        );
      },
    );
  }

  Widget _buildEmptyFeed() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.volunteer_activism_rounded,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          const Text(
            'אין בקשות עזרה כרגע',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _kMuted,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'בקשות חדשות יופיעו כאן — בדוק שוב בקרוב!',
            style: TextStyle(fontSize: 14, color: _kMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Request Card ───────────────────────────────────────────────────────────

  Widget _buildRequestCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';
    final desc = data['description'] as String? ?? '';
    final category = data['category'] as String? ?? 'other';
    final reqType = data['requesterType'] as String? ?? 'general';
    final urgency = data['urgency'] as String? ?? 'low';
    final isAnon = data['isAnonymous'] == true;
    final requesterName = data['requesterName'] as String? ?? 'אנונימי';
    final requesterImg = data['requesterImage'] as String?;
    final createdAt = data['createdAt'] as Timestamp?;
    final location = data['location'] as GeoPoint?;

    // Calculate distance
    String? distanceText;
    final cached = LocationService.cached;
    if (cached != null && location != null) {
      final meters = Geolocator.distanceBetween(
        cached.latitude,
        cached.longitude,
        location.latitude,
        location.longitude,
      );
      if (meters < 1000) {
        distanceText = '${meters.toInt()} מ׳';
      } else {
        distanceText = '${(meters / 1000).toStringAsFixed(1)} ק״מ';
      }
    }

    // Time ago
    String timeAgo = '';
    if (createdAt != null) {
      final diff = DateTime.now().difference(createdAt.toDate());
      if (diff.inMinutes < 60) {
        timeAgo = 'לפני ${diff.inMinutes} דקות';
      } else if (diff.inHours < 24) {
        timeAgo = 'לפני ${diff.inHours} שעות';
      } else {
        timeAgo = 'לפני ${diff.inDays} ימים';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border:
            urgency == 'high'
                ? Border.all(color: _kRed.withValues(alpha: 0.4), width: 1.5)
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: requester info + urgency
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEEEBFF),
                  backgroundImage:
                      isAnon ? null : safeImageProvider(requesterImg),
                  child:
                      isAnon || safeImageProvider(requesterImg) == null
                          ? Icon(
                            isAnon
                                ? Icons.person_outline_rounded
                                : Icons.person_rounded,
                            color: _kIndigo,
                            size: 22,
                          )
                          : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requesterName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _kDark,
                        ),
                      ),
                      if (timeAgo.isNotEmpty)
                        Text(
                          timeAgo,
                          style: const TextStyle(fontSize: 11, color: _kMuted),
                        ),
                    ],
                  ),
                ),
                // Urgency badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CommunityHubService.urgencyColor(
                      urgency,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    CommunityHubService.urgencyLabel(urgency),
                    style: TextStyle(
                      color: CommunityHubService.urgencyColor(urgency),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kDark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Description
            Text(
              desc,
              style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Bottom row: type badge + category + distance + button
            Row(
              children: [
                // Requester type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: CommunityHubService.requesterTypeColor(
                      reqType,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CommunityHubService.requesterTypeIcon(reqType),
                        size: 14,
                        color: CommunityHubService.requesterTypeColor(reqType),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        CommunityHubService.requesterTypeLabel(reqType),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CommunityHubService.requesterTypeColor(
                            reqType,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Category chip
                Icon(
                  CommunityHubService.categoryIcon(category),
                  size: 14,
                  color: _kMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  CommunityHubService.helpCategories.firstWhere(
                        (c) => c['id'] == category,
                        orElse: () => {'label': 'אחר'},
                      )['label']
                      as String,
                  style: const TextStyle(fontSize: 11, color: _kMuted),
                ),

                const Spacer(),

                // Distance
                if (distanceText != null) ...[
                  Icon(Icons.location_on_rounded, size: 14, color: _kIndigo),
                  const SizedBox(width: 2),
                  Text(
                    distanceText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kIndigo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // CTA button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => _claimRequest(doc),
                icon: const Icon(Icons.favorite_rounded, size: 18),
                label: const Text(
                  'אני יכול/ה לעזור!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map View ───────────────────────────────────────────────────────────────

  Widget _buildMapView() {
    final userPos = LocationService.cached;
    final center =
        userPos != null
            ? LatLng(userPos.latitude, userPos.longitude)
            : const LatLng(31.7683, 35.2137); // Default: Jerusalem

    return StreamBuilder<QuerySnapshot>(
      stream: CommunityHubService.streamOpenRequests(
        requesterType: _selectedTypeFilter,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('שגיאה בטעינת המפה'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kRed));
        }

        final docs = snap.data?.docs ?? [];
        final markers = <Marker>[];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final loc = data['location'] as GeoPoint?;
          if (loc == null) continue;

          final urgency = data['urgency'] as String? ?? 'low';
          final color = CommunityHubService.urgencyColor(urgency);

          markers.add(
            Marker(
              width: 40,
              height: 40,
              point: LatLng(loc.latitude, loc.longitude),
              child: GestureDetector(
                onTap: () => _showMapCardPreview(doc),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 13),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
            if (markers.isEmpty)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'אין התנדבויות עם מיקום באזור',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showMapCardPreview(DocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_buildRequestCard(doc)],
              ),
            ),
          ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB B — REQUEST HELP
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildRequestHelpTab() {
    final uid = _auth.currentUser?.uid;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active requests at the top — requires action from requester
          if (uid != null) _buildActiveRequestsSection(uid),
          _buildRequestForm(),
          const SizedBox(height: 28),
          _buildMyRequestsSection(),
        ],
      ),
    );
  }

  // ── Request Form ───────────────────────────────────────────────────────────

  Widget _buildRequestForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(Icons.add_circle_rounded, color: _kRed, size: 24),
              SizedBox(width: 8),
              Text(
                'פרסם בקשת עזרה',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'ספר/י לנו במה צריך עזרה — מתנדבים בסביבה יקבלו התראה.',
            style: TextStyle(fontSize: 13, color: _kMuted),
          ),
          const SizedBox(height: 10),

          // Positive reinforcement message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_emotions_rounded,
                    color: _kGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'כל הכבוד על השיתוף! הקהילה שלנו כאן בשבילך.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _kGreen.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Title field
          _formLabel('כותרת'),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            textAlign: TextAlign.start,
            decoration: _inputDecoration('לדוגמה: עזרה בתיקון ברז'),
          ),
          const SizedBox(height: 16),

          // Description field
          _formLabel('תיאור'),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            textAlign: TextAlign.start,
            decoration: _inputDecoration('תאר/י את הבקשה שלך בפירוט...'),
          ),
          const SizedBox(height: 16),

          // Category selector
          _formLabel('קטגוריה'),
          const SizedBox(height: 8),
          _buildCategoryGrid(),
          const SizedBox(height: 16),

          // Requester type (renamed label)
          _formLabel('עבור מי הסיוע?'),
          const SizedBox(height: 8),
          _buildRequesterTypeSelector(),
          const SizedBox(height: 16),

          // Urgency
          _formLabel('דחיפות'),
          const SizedBox(height: 8),
          _buildUrgencySelector(),
          const SizedBox(height: 16),

          // Target date (optional)
          _formLabel('מתי זה רלוונטי?'),
          const SizedBox(height: 6),
          _buildTargetDatePicker(),
          const SizedBox(height: 16),

          // Anonymous toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'בקשה אנונימית',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: _kDark,
                            ),
                          ),
                          Text(
                            'השם שלך יוסתר מהמתנדבים',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isAnonymous,
                      activeColor: _kIndigo,
                      onChanged: (v) => setState(() => _isAnonymous = v),
                    ),
                  ],
                ),
                if (_isAnonymous)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'השם שלך יוסתר מהמתנדב עד שתאשר את תחילת העבודה',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit + Preview buttons
          Row(
            children: [
              // Submit button
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submitRequest,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      _submitting ? 'שולח...' : 'שלח בקשת עזרה',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Preview button
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _showPreviewDialog,
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text(
                    'תצוגה\nמקדימה',
                    style: TextStyle(fontSize: 11, height: 1.2),
                    textAlign: TextAlign.center,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kIndigo,
                    side: const BorderSide(color: _kIndigo),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _kDark,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _kIndigo, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildCategoryGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          CommunityHubService.helpCategories.map((cat) {
            final id = cat['id'] as String;
            final label = cat['label'] as String;
            final isSelected = _selectedCategory == id;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? _kIndigo.withValues(alpha: 0.1)
                          : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? _kIndigo : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CommunityHubService.categoryIcon(id),
                      size: 16,
                      color: isSelected ? _kIndigo : _kMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? _kIndigo : _kDark,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildRequesterTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          CommunityHubService.requesterTypes.map((t) {
            final id = t['id'] as String;
            final label = t['label'] as String;
            final emoji = t['emoji'] as String;
            final isSelected = _selectedRequesterType == id;
            return GestureDetector(
              onTap: () => setState(() => _selectedRequesterType = id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? CommunityHubService.requesterTypeColor(
                            id,
                          ).withValues(alpha: 0.12)
                          : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        isSelected
                            ? CommunityHubService.requesterTypeColor(id)
                            : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color:
                            isSelected
                                ? CommunityHubService.requesterTypeColor(id)
                                : _kDark,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildUrgencySelector() {
    return Row(
      children: [
        _urgencyButton('low', 'רגיל', _kGreen),
        const SizedBox(width: 8),
        _urgencyButton('medium', 'בינוני', _kAmber),
        const SizedBox(width: 8),
        _urgencyButton('high', 'דחוף', _kRed),
      ],
    );
  }

  Widget _urgencyButton(String value, String label, Color color) {
    final isSelected = _selectedUrgency == value;

    // Darker tint for text/border when selected
    final Color darkColor;
    switch (value) {
      case 'high':
        darkColor = const Color(0xFFB91C1C); // dark red
      case 'medium':
        darkColor = const Color(0xFFB45309); // dark amber
      default:
        darkColor = const Color(0xFF047857); // dark green
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedUrgency = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                isSelected ? color.withValues(alpha: 0.14) : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? darkColor : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? darkColor : _kDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Target Date Picker ────────────────────────────────────────────────────

  Widget _buildTargetDatePicker() {
    final hasDate = _targetDate != null;
    final formatted = hasDate
        ? DateFormat('dd/MM/yyyy (EEEE)', 'he').format(_targetDate!)
        : null;

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _targetDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)),
          locale: const Locale('he'),
          helpText: 'בחר/י תאריך',
          cancelText: 'ביטול',
          confirmText: 'אישור',
        );
        if (picked != null && mounted) {
          setState(() => _targetDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasDate
              ? _kIndigo.withValues(alpha: 0.06)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasDate ? _kIndigo : Colors.grey[300]!,
            width: hasDate ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 18, color: hasDate ? _kIndigo : _kMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                formatted ?? 'לא חובה — בחר/י תאריך ספציפי',
                style: TextStyle(
                  fontSize: 13,
                  color: hasDate ? _kDark : Colors.grey[400],
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (hasDate)
              GestureDetector(
                onTap: () => setState(() => _targetDate = null),
                child: Icon(Icons.close_rounded,
                    size: 18, color: Colors.grey[400]),
              ),
          ],
        ),
      ),
    );
  }

  // ── Preview Dialog ────────────────────────────────────────────────────────

  void _showPreviewDialog() {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    if (title.isEmpty && desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('מלא/י כותרת ותיאור כדי לראות תצוגה מקדימה'),
          backgroundColor: _kAmber,
        ),
      );
      return;
    }

    final category = _selectedCategory;
    final reqType = _selectedRequesterType;
    final urgency = _selectedUrgency;
    final isAnon = _isAnonymous;
    final name = isAnon ? 'אנונימי' : (_userName.isNotEmpty ? _userName : 'שם המבקש');
    final targetDate = _targetDate;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.visibility_rounded, size: 20, color: _kIndigo),
                  SizedBox(width: 8),
                  Text(
                    'תצוגה מקדימה',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _kDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'כך הבקשה תיראה למתנדבים בפיד:',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),

              // Simulated card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kCardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: urgency == 'high'
                      ? Border.all(
                          color: _kRed.withValues(alpha: 0.4), width: 1.5)
                      : Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Requester row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFEEEBFF),
                          backgroundImage:
                              isAnon ? null : safeImageProvider(_userImage),
                          child: isAnon ||
                                  safeImageProvider(_userImage) == null
                              ? Icon(
                                  isAnon
                                      ? Icons.person_outline_rounded
                                      : Icons.person_rounded,
                                  color: _kIndigo,
                                  size: 20,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _kDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: CommunityHubService.urgencyColor(urgency)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            CommunityHubService.urgencyLabel(urgency),
                            style: TextStyle(
                              color:
                                  CommunityHubService.urgencyColor(urgency),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Title
                    Text(
                      title.isNotEmpty ? title : '(כותרת)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kMuted,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Target date (if set)
                    if (targetDate != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 13, color: _kIndigo),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd/MM/yyyy', 'he')
                                .format(targetDate),
                            style: const TextStyle(
                              fontSize: 11,
                              color: _kIndigo,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Badges row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                CommunityHubService.requesterTypeColor(
                                        reqType)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CommunityHubService.requesterTypeIcon(
                                    reqType),
                                size: 12,
                                color:
                                    CommunityHubService.requesterTypeColor(
                                        reqType),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                CommunityHubService.requesterTypeLabel(
                                    reqType),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      CommunityHubService
                                          .requesterTypeColor(reqType),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(CommunityHubService.categoryIcon(category),
                            size: 13, color: _kMuted),
                        const SizedBox(width: 3),
                        Text(
                          CommunityHubService.helpCategories.firstWhere(
                            (c) => c['id'] == category,
                            orElse: () => {'label': 'אחר'},
                          )['label'] as String,
                          style:
                              const TextStyle(fontSize: 10, color: _kMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Fake CTA (disabled)
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon:
                            const Icon(Icons.favorite_rounded, size: 16),
                        label: const Text(
                          'אני יכול/ה לעזור!',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _kGreen.withValues(alpha: 0.5),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Close button
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('סגור',
                      style: TextStyle(color: _kIndigo)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Active Requests Section (Requester side — top of Tab B) ────────────────

  Widget _buildActiveRequestsSection(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: CommunityHubService.streamMyActiveRequests(uid),
      builder: (context, snap) {
        if (snap.hasError || snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kRed.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    color: _kRed,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'הבקשות הפעילות שלי',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...docs.map((doc) => _buildActiveRequesterCard(doc)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveRequesterCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';
    final status = data['status'] as String? ?? '';
    final volunteerName = data['volunteerName'] as String? ?? 'מתנדב/ת';
    final volunteerId = data['volunteerId'] as String? ?? '';
    final completionPhotoUrl = data['completionPhotoUrl'] as String?;

    Color borderColor;
    Color bgColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'accepted':
        borderColor = const Color(0xFF8B5CF6);
        bgColor = const Color(0xFF8B5CF6).withValues(alpha: 0.05);
        statusIcon = Icons.directions_run_rounded;
        statusText = '$volunteerName בדרך אליך!';
      case 'in_progress':
        borderColor = _kIndigo;
        bgColor = _kIndigo.withValues(alpha: 0.05);
        statusIcon = Icons.handyman_rounded;
        statusText = 'המשימה בעיצומה...';
      case 'pending_confirmation':
        borderColor = _kRed;
        bgColor = _kRed.withValues(alpha: 0.04);
        statusIcon = Icons.notification_important_rounded;
        statusText = '$volunteerName סיים/ה — ממתין לאישורך!';
      default:
        borderColor = _kMuted;
        bgColor = Colors.grey.withValues(alpha: 0.05);
        statusIcon = Icons.info_rounded;
        statusText = status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor.withValues(alpha: 0.4),
          width: status == 'pending_confirmation' ? 2 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status badge row
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _kDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: borderColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: borderColor),
                    const SizedBox(width: 4),
                    Text(
                      status == 'accepted'
                          ? 'ממתין לאישורך'
                          : status == 'in_progress'
                          ? 'בביצוע'
                          : 'ממתין לאישור סיום',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: borderColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Status message
          Row(
            children: [
              Icon(statusIcon, size: 16, color: borderColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: borderColor,
                  ),
                ),
              ),
            ],
          ),

          // ── ACCEPTED: confirm start + chat + cancel ─────────────────
          if (status == 'accepted') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmStart(doc),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text(
                        'אשר התחלה',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (volunteerId.isNotEmpty)
                  _chatIconButton(volunteerId, volunteerName),
                TextButton(
                  onPressed: () => _cancelRequest(doc),
                  child: const Text(
                    'בטל',
                    style: TextStyle(color: _kMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],

          // ── IN_PROGRESS: chat button ────────────────────────────────
          if (status == 'in_progress') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                if (volunteerId.isNotEmpty)
                  _chatIconButton(volunteerId, volunteerName),
              ],
            ),
          ],

          // ── PENDING_CONFIRMATION: photo + confirm & thank + not yet ─
          if (status == 'pending_confirmation') ...[
            const SizedBox(height: 12),

            // Evidence photo
            if (completionPhotoUrl != null &&
                completionPhotoUrl.isNotEmpty) ...[
              GestureDetector(
                onTap: () => _showFullPhoto(context, completionPhotoUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    completionPhotoUrl,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 160,
                        color: Colors.grey[100],
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: _kIndigo,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder:
                        (_, __, ___) => Container(
                          height: 60,
                          color: Colors.grey[100],
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: _kMuted,
                            ),
                          ),
                        ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_rounded,
                      size: 12,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'תמונת הוכחה מהמתנדב/ת — לחץ/י להגדלה',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],

            // Confirm & Thank button (prominent)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => _confirmCompletion(doc),
                icon: const Icon(Icons.favorite_rounded, size: 20),
                label: const Text(
                  'אשר ושלח תודה! ❤️',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Not Yet button (secondary)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: () => _rejectCompletion(doc),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kMuted,
                  side: const BorderSide(color: _kMuted),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'עוד לא הסתיים',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Reusable chat icon button for requester cards.
  Widget _chatIconButton(String volunteerId, String volunteerName) {
    return IconButton(
      onPressed: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder:
                (_) => ChatScreen(
                  receiverId: volunteerId,
                  receiverName: volunteerName,
                ),
          ),
        );
      },
      icon: const Icon(Icons.chat_bubble_rounded, size: 20, color: _kIndigo),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  // ── My Requests Section ────────────────────────────────────────────────────

  Widget _buildMyRequestsSection() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.inbox_rounded, color: _kIndigo, size: 22),
            SizedBox(width: 8),
            Text(
              'הבקשות שלי',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: CommunityHubService.streamMyRequests(uid),
          builder: (context, snap) {
            if (snap.hasError) {
              return const SizedBox.shrink();
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: _kIndigo),
                ),
              );
            }

            final docs = snap.data?.docs ?? [];
            // Exclude active statuses — those are shown in the top section
            final filteredDocs =
                docs.where((d) {
                  final s =
                      (d.data() as Map<String, dynamic>?)?['status']
                          as String? ??
                      '';
                  return !CommunityHubService.activeStatuses.contains(s);
                }).toList();

            if (filteredDocs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'עוד לא פרסמת בקשות עזרה',
                    style: TextStyle(color: _kMuted, fontSize: 14),
                  ),
                ),
              );
            }

            return Column(
              children:
                  filteredDocs.map((d) => _buildMyRequestCard(d)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMyRequestCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final title = data['title'] as String? ?? '';
    final status = data['status'] as String? ?? 'open';
    final volunteerName = data['volunteerName'] as String?;
    final volunteerId = data['volunteerId'] as String? ?? '';
    final reqType = data['requesterType'] as String? ?? 'general';
    final thankYouNote = data['thankYouNote'] as String?;
    final completionPhotoUrl = data['completionPhotoUrl'] as String?;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'open':
        statusColor = _kAmber;
        statusLabel = 'ממתין למתנדב';
        statusIcon = Icons.hourglass_top_rounded;
      case 'accepted':
        statusColor = const Color(0xFF8B5CF6);
        statusLabel =
            volunteerName != null
                ? '$volunteerName רוצה לעזור — אשר/י'
                : 'ממתין לאישור';
        statusIcon = Icons.person_add_alt_rounded;
      case 'in_progress':
        statusColor = _kIndigo;
        statusLabel = 'בטיפול — $volunteerName';
        statusIcon = Icons.handyman_rounded;
      case 'pending_confirmation':
        statusColor = _kRed;
        statusLabel = '$volunteerName סיים/ה — ממתין לאישורך';
        statusIcon = Icons.notification_important_rounded;
      case 'completed':
        statusColor = _kGreen;
        statusLabel = 'הושלם';
        statusIcon = Icons.check_circle_rounded;
      case 'cancelled':
        statusColor = _kMuted;
        statusLabel = 'בוטל';
        statusIcon = Icons.cancel_rounded;
      default:
        statusColor = _kMuted;
        statusLabel = status;
        statusIcon = Icons.info_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: status == 'pending_confirmation' ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CommunityHubService.requesterTypeIcon(reqType),
                size: 18,
                color: CommunityHubService.requesterTypeColor(reqType),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _kDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Pending Confirmation prompt ────────────────────────────────
          if (status == 'pending_confirmation') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kAmber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kAmber.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    'האם ${volunteerName ?? 'המתנדב/ת'} עזר/ה לך?',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kDark,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // ── Evidence photo ────────────────────────────────
                  if (completionPhotoUrl != null &&
                      completionPhotoUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _showFullPhoto(context, completionPhotoUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          completionPhotoUrl,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 140,
                              color: Colors.grey[100],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: _kIndigo,
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                          errorBuilder:
                              (_, __, ___) => Container(
                                height: 60,
                                color: Colors.grey[100],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_rounded,
                                    color: _kMuted,
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_rounded,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'תמונת הוכחה מהמתנדב/ת — לחץ/י להגדלה',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: ElevatedButton.icon(
                            onPressed: () => _confirmCompletion(doc),
                            icon: const Icon(Icons.favorite_rounded, size: 18),
                            label: const Text(
                              'אשר ותודה',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          onPressed: () => _rejectCompletion(doc),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kMuted,
                            side: const BorderSide(color: _kMuted),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'עוד לא',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // ── Accepted — Confirm Start prompt ───────────────────────────
          if (status == 'accepted') ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmStart(doc),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text(
                        'אשר התחלה',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Chat with volunteer
                if (volunteerId.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder:
                              (_) => ChatScreen(
                                receiverId: volunteerId,
                                receiverName: volunteerName ?? 'מתנדב/ת',
                              ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 20,
                      color: _kIndigo,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                // Cancel
                TextButton(
                  onPressed: () => _cancelRequest(doc),
                  child: const Text(
                    'בטל',
                    style: TextStyle(color: _kMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],

          // ── In Progress — chat only ───────────────────────────────────
          if (status == 'in_progress')
            Row(
              children: [
                const Spacer(),
                if (volunteerId.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder:
                              (_) => ChatScreen(
                                receiverId: volunteerId,
                                receiverName: volunteerName ?? 'מתנדב/ת',
                              ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 20,
                      color: _kIndigo,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),

          // ── Open — cancel button ──────────────────────────────────────
          if (status == 'open')
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => _cancelRequest(doc),
                  child: const Text(
                    'בטל',
                    style: TextStyle(color: _kMuted, fontSize: 13),
                  ),
                ),
              ],
            ),

          // ── Completed — show thank you note if exists ─────────────────
          if (status == 'completed' && thankYouNote != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    size: 16,
                    color: _kGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      thankYouNote,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _kDark,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmStart(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final data = doc.data() as Map<String, dynamic>? ?? {};
    final volunteerName = data['volunteerName'] as String? ?? 'מתנדב/ת';

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('אישור התחלת עזרה'),
            content: Text(
              'לאשר ל-$volunteerName להתחיל לעזור?\n\n'
              'לאחר האישור, המתנדב/ת יקבל/ת התראה להתחיל.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kIndigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('כן, אשר/י!'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    final error = await CommunityHubService.confirmStart(
      requestId: doc.id,
      requesterId: user.uid,
    );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _kRed));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('המתנדב/ת קיבל/ה אישור להתחיל!'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rejectCompletion(DocumentSnapshot doc) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final error = await CommunityHubService.rejectCompletion(
      requestId: doc.id,
      requesterId: user.uid,
    );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _kRed));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('המשימה חזרה לסטטוס פעיל — המתנדב/ת יודע/ת'),
          backgroundColor: _kIndigo,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelRequest(DocumentSnapshot doc) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final error = await CommunityHubService.cancelRequest(doc.id, uid);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error), backgroundColor: _kRed));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הבקשה בוטלה'), backgroundColor: _kMuted),
      );
    }
  }

  // ── Celebration Overlay ────────────────────────────────────────────────────

  Widget _buildCelebrationOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder:
                (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _kRed.withValues(alpha: 0.3),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  const Text(
                    'תודה רבה!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _kDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ההתנדבות אושרה בהצלחה',
                    style: TextStyle(fontSize: 15, color: _kMuted),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kGreen, _kIndigo],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '+$_celebrationXp XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sticky Tab Bar Delegate
// ═════════════════════════════════════════════════════════════════════════════

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: _kBg, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
