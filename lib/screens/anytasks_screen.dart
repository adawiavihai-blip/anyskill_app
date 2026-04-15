/// AnyTasks 3.0 — Main Screen
///
/// Two-tab layout (follows CommunityHubScreen pattern):
///   Tab 1: "גלה משימות" — Browse open tasks with category filter chips
///   Tab 2: "המשימות שלי" — Tasks I posted + tasks I claimed
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/anytask.dart';
import '../services/anytask_service.dart';
import '../services/anytask_category_service.dart';
import '../constants.dart';
import '../widgets/anytask_card.dart';
import 'anytask_detail_screen.dart';
import 'anytask_post_screen.dart';

class AnytasksScreen extends StatefulWidget {
  const AnytasksScreen({super.key});

  @override
  State<AnytasksScreen> createState() => _AnytasksScreenState();
}

class _AnytasksScreenState extends State<AnytasksScreen>
    with SingleTickerProviderStateMixin {
  static const _kIndigo  = Color(0xFF6366F1);
  static const _kDark    = Color(0xFF1A1A2E);
  static const _kMuted   = Color(0xFF6B7280);
  static const _kScaffold = Color(0xFFF4F7F9);

  late final TabController _tabCtrl;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  String? _categoryFilter;
  List<Map<String, dynamic>> _categories = ANYTASK_CATEGORIES;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await AnytaskCategoryService.getAll();
    if (mounted) setState(() => _categories = cats);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _openDetail(String taskId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnytaskDetailScreen(taskId: taskId)),
    );
  }

  void _openPostScreen() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AnytaskPostScreen()),
    );
    if (posted == true && mounted) {
      _tabCtrl.animateTo(1); // Switch to "My Tasks" tab
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kScaffold,
      appBar: AppBar(
        title: const Text('AnyTasks'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _kDark,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _kIndigo,
          indicatorWeight: 3,
          labelColor: _kIndigo,
          unselectedLabelColor: _kMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'גלה משימות'),
            Tab(text: 'המשימות שלי'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildBrowseTab(),
          _buildMyTasksTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPostScreen,
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('פרסם משימה', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 1: Browse Open Tasks
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBrowseTab() {
    return Column(
      children: [
        // Category filter chips
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _filterChip('הכל', null),
              ..._categories.map((c) =>
                  _filterChip(c['nameHe'] as String? ?? '', c['id'] as String?)),
            ],
          ),
        ),

        // Task feed
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: AnytaskService.streamOpenTasks(category: _categoryFilter),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('שגיאה בטעינת משימות'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;

              // Filter out own tasks (creator shouldn't see their own in browse)
              final filtered = docs.where((d) {
                final data = d.data() as Map<String, dynamic>? ?? {};
                return data['creatorId'] != _uid;
              }).toList();

              if (filtered.isEmpty) {
                return _emptyState(
                  icon: Icons.search_off_rounded,
                  title: 'אין משימות זמינות כרגע',
                  subtitle: 'נסה קטגוריה אחרת או פרסם משימה בעצמך!',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 100),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final task = AnyTask.fromFirestore(filtered[i]);
                  return AnytaskCard(
                    task: task,
                    onTap: () => _openDetail(task.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String? catId) {
    final selected = _categoryFilter == catId;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _categoryFilter = catId),
        selectedColor: _kIndigo.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? _kIndigo : _kMuted,
        ),
        side: BorderSide(color: selected ? _kIndigo : Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 2: My Tasks (created + claimed)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMyTasksTab() {
    if (_uid.isEmpty) {
      return _emptyState(
        icon: Icons.login_rounded,
        title: 'יש להתחבר',
        subtitle: 'התחבר כדי לראות את המשימות שלך',
      );
    }

    return CustomScrollView(
      slivers: [
        // ── Header: Tasks I'm working on (as provider) ───────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'משימות שאני מבצע',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: StreamBuilder<QuerySnapshot>(
            stream: AnytaskService.streamMyActiveProviderTasks(_uid),
            builder: (_, snap) {
              if (snap.hasError) return const SizedBox.shrink();
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.inbox_rounded, color: _kMuted, size: 20),
                        SizedBox(width: 10),
                        Text('אין משימות פעילות', style: TextStyle(color: _kMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: docs.map((d) {
                  final task = AnyTask.fromFirestore(d);
                  return AnytaskCard(
                    task: task,
                    showCreator: true,
                    onTap: () => _openDetail(task.id),
                  );
                }).toList(),
              );
            },
          ),
        ),

        // ── Header: Tasks I posted (as creator) ──────────────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'משימות שפרסמתי',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: StreamBuilder<QuerySnapshot>(
            stream: AnytaskService.streamMyCreatedTasks(_uid),
            builder: (_, snap) {
              if (snap.hasError) return const SizedBox.shrink();
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }

              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return _emptyState(
                  icon: Icons.post_add_rounded,
                  title: 'עוד לא פרסמת משימות',
                  subtitle: 'לחץ על "פרסם משימה" כדי להתחיל',
                );
              }

              return Column(
                children: docs.map((d) {
                  final task = AnyTask.fromFirestore(d);
                  return AnytaskCard(
                    task: task,
                    showCreator: false,
                    onTap: () => _openDetail(task.id),
                  );
                }).toList(),
              );
            },
          ),
        ),

        // Bottom spacer for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _kMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: _kMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
