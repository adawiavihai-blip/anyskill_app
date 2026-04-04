import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import '../services/volunteer_service.dart';
import 'category_results_screen.dart';
import 'expert_profile_screen.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import '../utils/safe_image_provider.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late FirebaseAuth _auth;
  late FirebaseFirestore _db;
  bool _isVolunteer = false;
  bool _isProvider = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance;
    _db = FirebaseFirestore.instance;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!mounted) return;
      setState(() {
        _isVolunteer = (doc.data()?['isVolunteer'] as bool?) ?? false;
        _isProvider = (doc.data()?['isProvider'] as bool?) ?? false;
      });
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _toggleVolunteerStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }

    if (!_isProvider) {
      _showNeedProviderDialog();
      return;
    }

    // Show info modal BEFORE joining (only when joining, not leaving)
    if (!_isVolunteer) {
      final proceed = await _showVolunteerInfoModal();
      if (!proceed) return;
    }

    setState(() => _isLoading = true);
    try {
      final newVal = !_isVolunteer;
      await _db
          .collection('users')
          .doc(user.uid)
          .update({'isVolunteer': newVal});
      if (!mounted) return;
      setState(() => _isVolunteer = newVal);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVal
                ? '✓ הצטרפת לתוכנית ההתנדבות!'
                : '✓ יצאת מתוכנית ההתנדבות',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Volunteer Benefits Info Modal ──────────────────────────────────────────

  Future<bool> _showVolunteerInfoModal() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ────────────────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF6366F1)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Icon(Icons.volunteer_activism,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'הצטרף לתוכנית ההתנדבות',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // ── Benefit 1: XP ───────────────────────────────────────
              _benefitRow(
                icon: Icons.star_rounded,
                color: const Color(0xFFF59E0B),
                title: '+${VolunteerService.volunteerXpReward} XP לכל משימה',
                body: 'קבל נקודות ניסיון על כל התנדבות מאושרת ועלה בדרגה מהר יותר.',
              ),
              const SizedBox(height: 12),

              // ── Benefit 2: Badge ────────────────────────────────────
              _benefitRow(
                icon: Icons.verified,
                color: const Color(0xFF10B981),
                title: 'תג "מתנדב פעיל" בפרופיל',
                body: 'תג בולט בפרופיל שלך כל עוד התנדבת בחודש האחרון — נראה לכל הלקוחות.',
              ),
              const SizedBox(height: 12),

              // ── Benefit 3: Search Priority ──────────────────────────
              _benefitRow(
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF6366F1),
                title: 'עדיפות בתוצאות החיפוש',
                body: 'מתנדבים פעילים מקבלים דחיפה אוטומטית בדירוג החיפוש ומופיעים גבוה יותר.',
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'המשימות מאושרות על ידי הלקוח בלבד.\n'
                'לא ניתן להתנדב לעצמך.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // ── CTA ─────────────────────────────────────────────────
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'אני רוצה להתנדב!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('אולי אחר כך',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Widget _benefitRow({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ],
    );
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('עליך להיכנס לחשבון'),
        content: const Text('כדי להתנדב עליך להיות מחובר לאפליקציה.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('סגור'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.of(context, rootNavigator: true).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('היכנס'),
          ),
        ],
      ),
    );
  }

  void _showNeedProviderDialog() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('הרשמה כנותן שירות'),
        content: const Text(
          'כדי להתנדב עליך להירשם תחילה כנותן שירות בפרופיל שלך.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('סגור'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(c);
              final user = _auth.currentUser;
              if (user == null) return;
              final doc = await _db.collection('users').doc(user.uid).get();
              if (!mounted) return;
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(
                    userData: doc.data() ?? {},
                  ),
                ),
              );
            },
            child: const Text('ערוך פרופיל'),
          ),
        ],
      ),
    );
  }

  void _showHelpRequestDialog() {
    String? selectedCategory;
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        title: const Text('בקש עזרה מהקהילה'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'בחר את קטגוריית השירות שאתה זקוק לה:',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (ctx, setState) => DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('בחר קטגוריה...'),
                  value: selectedCategory,
                  items: APP_CATEGORIES
                      .map((cat) => DropdownMenuItem(
                            value: cat['name'] as String,
                            child: Text(cat['name'] as String),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => selectedCategory = val),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'תיאור קצר (אופציונלי):',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'תאר את הבקשה שלך...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedCategory == null || selectedCategory!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('בחר קטגוריה')),
                );
                return;
              }
              Navigator.pop(c);
              await _submitHelpRequest(
                selectedCategory!,
                descController.text,
              );
            },
            child: const Text('שלח בקשה'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitHelpRequest(
    String category,
    String description,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }

    try {
      // Write help request
      await _db.collection('help_requests').add({
        'userId': user.uid,
        'category': category,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      // Query active volunteers in this category
      final volunteersSnap = await _db
          .collection('users')
          .where('isVolunteer', isEqualTo: true)
          .where('isOnline', isEqualTo: true)
          .where('serviceType', isEqualTo: category)
          .limit(20)
          .get();

      int notificationCount = 0;
      for (final doc in volunteersSnap.docs) {
        final volunteerId = doc.id;
        // Anti-fraud: skip if the volunteer IS the requester
        if (volunteerId == user.uid) continue;
        await _db.collection('notifications').add({
          'userId': volunteerId,
          'title': '🤝 בקשת עזרה חדשה!',
          'body': 'יש בקשת עזרה בקטגוריית "$category" - תוכל לעזור?',
          'type': 'help_request',
          'relatedUserId': user.uid,
          'category': category,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        notificationCount++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notificationCount > 0
                ? 'בקשת העזרה נשלחה ל-$notificationCount מתנדבים פעילים ✓'
                : 'בקשת העזרה נשלחה! אנחנו נחפש מתנדבים זמינים.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: CustomScrollView(
        slivers: [
          // ── Collapsing hero image AppBar ─────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: const Text(
                'AnySkill למען הקהילה',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1593113598332-cd288d649433?w=800',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF6366F1)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.volunteer_activism,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Gradient scrim so title stays readable
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body content ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Mission statement ───────────────────────────────────
                  const Text(
                    'AnySkill למען הקהילה',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'יוזמה ייחודית שבה נותני השירות שלנו מתנדבים מרצונם '
                    'ומעניקים את שירותיהם המקצועיים ללא כל עלות לאנשים '
                    'שזקוקים לעזרה בקהילה. כאן תמצאו שיפוץ, ניקיון, '
                    'עיצוב, הוראה ועוד — הכל ממקום של נתינה אמיתית.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF4B5563),
                      height: 1.65,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Three highlight cards ───────────────────────────────
                  _HighlightCard(
                    icon: Icons.favorite,
                    color: const Color(0xFFEF4444),
                    title: 'ממקום של לב',
                    body:
                        'נותני השירות שלנו בוחרים להתנדב — ללא תשלום, ללא תמורה.',
                  ),
                  const SizedBox(height: 12),
                  _HighlightCard(
                    icon: Icons.verified_user_outlined,
                    color: const Color(0xFF6366F1),
                    title: 'נותני שירות מאומתים',
                    body:
                        'כל מתנדב עבר אימות זהות ואישור מקצועי על ידי AnySkill.',
                  ),
                  const SizedBox(height: 12),
                  _HighlightCard(
                    icon: Icons.groups_outlined,
                    color: const Color(0xFF10B981),
                    title: 'קהילה שמחזקת קהילה',
                    body:
                        'כל שירות שניתן מחזק את הקשר בין שכנים ובונה עתיד טוב יותר.',
                  ),

                  const SizedBox(height: 36),

                  // ── Live Volunteers Strip ────────────────────────────────
                  const Text(
                    'מתנדבים פעילים',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildVolunteerStrip(),

                  const SizedBox(height: 36),

                  // ── CTA buttons ──────────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _toggleVolunteerStatus,
                    icon: const Icon(Icons.volunteer_activism, size: 20),
                    label: Text(
                      _isVolunteer ? 'אני כבר מתנדב ✓' : 'אני רוצה להתנדב',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),

                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: _showHelpRequestDialog,
                    icon: const Icon(Icons.help, size: 20),
                    label: const Text(
                      'אני צריך עזרה',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context, rootNavigator: true)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const CategoryResultsScreen(
                              categoryName: 'volunteer',
                              volunteerOnly: true,
                            ),
                          ),
                        ),
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text(
                      'חיפוש נותני שירות מתנדבים',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      minimumSize: const Size(double.infinity, 54),
                      side: const BorderSide(
                        color: Color(0xFF10B981),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'הצטרפו אלינו לשינוי',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolunteerStrip() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('users')
          .where('isVolunteer', isEqualTo: true)
          .where('isOnline', isEqualTo: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('שגיאה בטעינת המתנדבים'),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: SizedBox(
                height: 40,
                width: 40,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final volunteers = snap.data?.docs ?? [];
        if (volunteers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('אין מתנדבים פעילים כרגע'),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var doc in volunteers)
                  _buildVolunteerChip(doc.data() as Map<String, dynamic>, doc.id),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVolunteerChip(Map<String, dynamic> userData, String uid) {
    final name = userData['name'] as String? ?? 'מתנדב';
    final rawImg = userData['profileImage'];
    final imageUrl = (rawImg is String && rawImg.isNotEmpty) ? rawImg : null;
    final category = userData['serviceType'] as String? ?? '';
    debugPrint('[Volunteer] $name (uid=$uid) img=${imageUrl != null ? "${imageUrl.length} chars" : "NULL"}');

    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => ExpertProfileScreen(
            expertId: uid,
            expertName: name,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFFEEEBFF),
              backgroundImage: safeImageProvider(imageUrl),
              child: safeImageProvider(imageUrl) == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Column(
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
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

  @override
  void dispose() {
    super.dispose();
  }
}

// ── Highlight info card ───────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _HighlightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ],
      ),
    );
  }
}
