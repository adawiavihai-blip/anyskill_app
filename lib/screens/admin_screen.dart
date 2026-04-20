import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'business_ai_screen.dart';
import 'xp_manager_screen.dart';
import 'dispute_resolution_screen.dart';
import 'system_performance_tab.dart';
import 'registration_funnel_tab.dart';
import 'live_activity_tab.dart';
import 'admin_design_tab.dart';
import 'admin_demo_experts_tab.dart';
import 'admin_brand_assets_tab.dart';
import 'admin_payouts_tab.dart';
import 'admin_banners_tab.dart';
import 'admin_pro_tab.dart';
import 'admin_billing_tab.dart';
import 'admin_sounds_tab.dart';
import 'admin_support_inbox_tab.dart';
import 'admin_ai_ceo_tab.dart';
import 'admin_insights_tab.dart';
import 'admin_monetization_tab.dart';
import 'admin_id_verification_tab.dart';
import 'admin_categories_management_tab.dart';
import 'categories_v3/admin_categories_v3_tab.dart';
import 'categories_v3/feature_flag.dart';
import 'admin_private_feedback_tab.dart';
import 'admin_stories_management_tab.dart';
import 'admin_academy_management_tab.dart';
import 'admin_chat_guard_tab.dart';
import 'admin_active_chats_tab.dart';
import 'admin_withdrawals_tab.dart';
import 'admin_users_tab.dart';
import 'admin_agent_management_tab.dart';
import '../providers/admin_users_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _sectionIndex = 0; // 0 = ניהול, 1 = תוכן, 2 = מערכת

  @override
  void initState() {
    super.initState();
    _syncAppVersion();
  }

  Future<void> _syncAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.split('+').first;
      if (version.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('admin')
          .doc('settings')
          .set({'latestVersion': version}, SetOptions(merge: true));
      debugPrint('Admin: synced latestVersion -> $version');
    } catch (e) {
      debugPrint('Admin: version sync failed - $e');
    }
  }

  // _streamGuard, loaders, insights/monetization/categories/verification
  // → extracted to separate tab files (Phase 3+4)

  void _showBroadcastDialog() {
    final TextEditingController broadcastController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text("שידור גלובלי"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ההודעה תופיע כבאנר כחול לכל המשתמשים בדף הבית.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: broadcastController,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "כתוב את ההודעה כאן...",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(ctx),
              child: const Text("ביטול"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent),
              onPressed: isSending
                  ? null
                  : () async {
                      final msg = broadcastController.text.trim();
                      if (msg.isEmpty) return;
                      setDlgState(() => isSending = true);

                      // 1. Write banner (shown immediately to all online users)
                      await FirebaseFirestore.instance
                          .collection('admin')
                          .doc('settings')
                          .set({'broadcastMessage': msg},
                              SetOptions(merge: true));

                      // 2. Log to broadcast_history
                      await FirebaseFirestore.instance
                          .collection('broadcast_history')
                          .add({
                        'message':   msg,
                        'sentAt':    FieldValue.serverTimestamp(),
                        'sentBy':    'admin',
                        'platform':  'in-app-banner',
                      });

                      // 3. Call Cloud Function to push FCM to all users
                      try {
                        await FirebaseFunctions.instance
                            .httpsCallable('sendGlobalBroadcast')
                            .call({'message': msg});
                      } catch (e) {
                        debugPrint('Broadcast FCM error (non-fatal): $e');
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('שידור נשלח בהצלחה!'),
                            backgroundColor: Colors.blueAccent,
                          ),
                        );
                      }
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white),
              label: const Text("שדר עכשיו",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _buildSectionToggle(),
        ),
        titleSpacing: 8,
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: Colors.blueAccent, size: 28),
            onPressed: _showBroadcastDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
              index: _sectionIndex,
              children: [
                _buildManagementSection(),
                _buildContentSection(),
                _buildSystemSection(),
                const AdminDesignTab(),
                const AdminAiCeoTab(),
                const AdminAgentManagementTab(),
              ],
            ),
    );
  }

  // ── Section toggle (SegmentedButton in AppBar title) ────────────────────────

  Widget _buildSectionToggle() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          label: Text('ניהול'),
          icon: Icon(Icons.manage_accounts_rounded, size: 15),
        ),
        ButtonSegment(
          value: 1,
          label: Text('תוכן'),
          icon: Icon(Icons.movie_filter_rounded, size: 15),
        ),
        ButtonSegment(
          value: 2,
          label: Text('מערכת'),
          icon: Icon(Icons.settings_rounded, size: 15),
        ),
        ButtonSegment(
          value: 3,
          label: Text('עיצוב'),
          icon: Icon(Icons.design_services_rounded, size: 15),
        ),
        ButtonSegment(
          value: 4,
          label: Text('אילון'),
          icon: Icon(Icons.psychology_rounded, size: 15),
        ),
        ButtonSegment(
          value: 5,
          label: Text('סוכני תמיכה'),
          icon: Icon(Icons.support_agent_rounded, size: 15),
        ),
      ],
      selected: {_sectionIndex},
      onSelectionChanged: (s) => setState(() => _sectionIndex = s.first),
      style: ButtonStyle(
        tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
        visualDensity:  VisualDensity.compact,
        textStyle:      WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Management section (ניהול) — 15 tabs ──────────────────────────────────

  Widget _buildManagementSection() {
    // select() — only rebuilds when these specific counts change.
    final customers = ref.watch(
        adminUsersNotifierProvider.select((s) => s.totalCustomers));
    final providers = ref.watch(
        adminUsersNotifierProvider.select((s) => s.totalProviders));

    return DefaultTabController(
      length: 15,
      child: Column(
        children: [
          // Search bar — updates the Riverpod provider, NOT local setState
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
            child: TextField(
              onChanged: (v) => ref
                  .read(adminUsersNotifierProvider.notifier)
                  .setSearch(v),
              decoration: InputDecoration(
                hintText: "חפש שם, מייל או מזהה...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Stats badges
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pulseBadge("👥 $customers לקוחות"),
                _pulseBadge("🛠️ $providers ספקים"),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Tabs
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor:     Colors.blueAccent,
            indicatorColor: Colors.blueAccent,
            tabs: [
              Tab(text: "הכל"),
              Tab(text: "לקוחות"),
              Tab(text: "ספקים"),
              Tab(text: "חסומים"),
              Tab(text: "מחלוקות 🔴"),
              Tab(text: "משיכות 💸"),
              Tab(text: "XP & רמות 🎮"),
              Tab(text: "אימות זהות 🪪"),
              Tab(text: "משפך הרשמה 📈"),
              Tab(text: "לייב פיד 📡"),
              Tab(text: "צ'אטים 💬"),
              Tab(text: "דמו ★"),
              Tab(text: "Pro ⭐"),
              Tab(text: "בינה עסקית 🧠"),
              Tab(text: "תיבת פניות 📮"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const AdminUsersTab(filter: AdminUserFilter.all),
                const AdminUsersTab(filter: AdminUserFilter.customers),
                const AdminUsersTab(filter: AdminUserFilter.providers),
                const AdminUsersTab(filter: AdminUserFilter.banned),
                const DisputeResolutionScreen(),
                const AdminWithdrawalsTab(),
                const XpManagerScreen(),
                const AdminIdVerificationTab(),
                const RegistrationFunnelTab(),
                const LiveActivityTab(),
                const AdminActiveChatsTab(),
                const AdminDemoExpertsTab(),
                const AdminProTab(),
                const BusinessAiScreen(),
                const AdminSupportInboxTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Content section (תוכן) — 4 tabs ─────────────────────────────────────

  Widget _buildContentSection() {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor:     Color(0xFFD97706),
            indicatorColor: Color(0xFFD97706),
            tabs: [
              Tab(icon: Icon(Icons.auto_stories_rounded, size: 18), text: 'סטוריז 📸'),
              Tab(icon: Icon(Icons.school_rounded,       size: 18), text: 'אקדמיה 🎓'),
              Tab(icon: Icon(Icons.videocam_rounded,     size: 18), text: 'וידאו ✅'),
              Tab(icon: Icon(Icons.lock_outline_rounded, size: 18), text: 'משוב פרטי 🔒'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const AdminStoriesManagementTab(),
                const AdminAcademyManagementTab(),
                _buildVideoVerificationTab(),
                const AdminPrivateFeedbackTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── System section (מערכת) — 7 tabs ──────────────────────────────────────

  Widget _buildSystemSection() {
    return DefaultTabController(
      length: 10,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor:     Color(0xFF7C3AED),
            indicatorColor: Color(0xFF7C3AED),
            tabs: [
              Tab(text: "קטגוריות 🏷️"),
              Tab(text: "באנרים 🎨"),
              Tab(text: "מוניטיזציה 💰"),
              Tab(text: "כספים 💵"),
              Tab(text: "תובנות 📊"),
              Tab(text: "ביצועים 🖥️"),
              Tab(text: "מיתוג 🎨"),
              Tab(text: "חסימות 🛡️"),
              Tab(text: "תשלומים 💳"),
              Tab(text: "צלילים 🔊"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Categories v3 (Section 45) — gated by hard-coded UID flag.
                // Whitelisted admin → premium v3 workspace.
                // Everyone else → legacy AdminCategoriesManagementTab.
                if (CategoriesV3FeatureFlag.isCategoriesV3Enabled)
                  const AdminCategoriesV3Tab()
                else
                  const AdminCategoriesManagementTab(),
                const AdminBannersTab(),
                const AdminMonetizationTab(),
                const AdminBillingTab(),
                const AdminInsightsTab(),
                const SystemPerformanceTab(),
                const AdminBrandAssetsTab(),
                const AdminChatGuardTab(),
                const AdminPayoutsTab(),
                const AdminSoundsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pulseBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildVideoVerificationTab() => const _VideoVerificationTabContent();
}

// ── Sync Phones Button (self-contained stateful widget) ──────────────────────
class _SyncPhonesButton extends StatefulWidget {
  const _SyncPhonesButton();
  @override
  State<_SyncPhonesButton> createState() => _SyncPhonesButtonState();
}

class _SyncPhonesButtonState extends State<_SyncPhonesButton> {
  bool _syncing = false;
  String _result = '';

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _result = '';
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
      final res = await fn.httpsCallable('syncUserPhones').call();
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _syncing = false;
        _result =
            '✅ עודכנו ${data['updated'] ?? 0} משתמשים מתוך ${data['scanned'] ?? 0}';
      });
    } catch (e) {
      setState(() {
        _syncing = false;
        _result = '❌ שגיאה: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: _syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.phone_rounded, size: 16),
          label: Text(_syncing ? 'מסנכרן...' : 'סנכרן מספרי טלפון'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: _syncing ? null : _sync,
        ),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _result,
            style: TextStyle(
              fontSize: 12,
              color: _result.startsWith('✅') ? Colors.teal : Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ── Video Verification Admin Tab ──────────────────────────────────────────────
// Fetches all users with a verificationVideoUrl that hasn't yet been approved.
class _VideoVerificationTabContent extends StatelessWidget {
  const _VideoVerificationTabContent();

  Future<void> _approve(BuildContext context, String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'videoVerifiedByAdmin': true,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ הסרטון אושר — יופיע בפרופיל המומחה'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _reject(BuildContext context, String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'verificationVideoUrl': FieldValue.delete(),
      'videoVerifiedByAdmin': false,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🗑️ הסרטון נדחה והוסר'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('isProvider', isEqualTo: true)
          .limit(200)
          .get(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('שגיאה בטעינת וידאו', style: TextStyle(color: Colors.grey[500])));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = (snap.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>;
          final url  = data['verificationVideoUrl'] as String?;
          final approved = data['videoVerifiedByAdmin'] as bool? ?? false;
          return url != null && url.isNotEmpty && !approved;
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_rounded, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text('אין סרטוני אימות ממתינים',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc  = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final uid  = doc.id;
            final name = data['name'] as String? ?? uid;
            final videoUrl = data['verificationVideoUrl'] as String;
            final serviceType = data['serviceType'] as String? ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15)),
                              if (serviceType.isNotEmpty)
                                Text(serviceType,
                                    style: const TextStyle(
                                        fontSize: 13, color: Color(0xFF6366F1))),
                              Text(uid,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Text('ממתין לאישור',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(videoUrl);
                              if (uri != null) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.play_circle_outline_rounded,
                                size: 18),
                            label: const Text('צפה בסרטון'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6366F1),
                              side: const BorderSide(color: Color(0xFF6366F1)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _approve(context, uid),
                            icon: const Icon(Icons.check_circle_outline_rounded,
                                size: 18),
                            label: const Text('אשר סרטון'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _reject(context, uid),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          tooltip: 'דחה וסלק',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}