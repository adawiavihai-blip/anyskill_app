/// AnySkill — Dog Profile List Screen (Pet Stay Tracker v13.0.0)
///
/// Owner-only. Shows all of the signed-in user's dog profiles as cards,
/// plus a FAB to add a new one. Tap a card → edit; long-press → delete.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../utils/safe_image_provider.dart';
import '../models/dog_profile.dart';
import '../services/dog_profile_service.dart';
import 'dog_profile_builder_screen.dart';

class DogProfileListScreen extends StatelessWidget {
  const DogProfileListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('הכלבים שלי')),
        body: const Center(child: Text('יש להתחבר')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'הכלבים שלי',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        centerTitle: true,
      ),
      body: StreamBuilder<List<DogProfile>>(
        stream: DogProfileService.instance.streamForOwner(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('שגיאה: ${snap.error}'));
          }
          final dogs = snap.data ?? const [];
          if (dogs.isEmpty) return const _EmptyState();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: dogs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _DogCard(
              dog: dogs[i],
              onTap: () => _openBuilder(context, existing: dogs[i]),
              onDelete: () => _confirmDelete(context, uid, dogs[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('הוסף כלב'),
        onPressed: () => _openBuilder(context),
      ),
    );
  }

  void _openBuilder(BuildContext context, {DogProfile? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DogProfileBuilderScreen(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String uid,
    DogProfile dog,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('למחוק את הפרופיל?'),
        content: Text(
          'הפרופיל של ${dog.name} יימחק. פרטים שכבר נשלחו לספק במסגרת הזמנה קיימת לא יושפעו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (dog.id == null) return;
    await DogProfileService.instance.delete(uid, dog.id!);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הפרופיל נמחק')),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pets_rounded,
                size: 48,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'עדיין אין כלבים',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'בנה פרופיל מלא לכלב שלך — השם, האוכל, הרגלים, תרופות\nוהכל יועבר אוטומטית לנותן השירות בכל הזמנה.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _DogCard extends StatelessWidget {
  final DogProfile dog;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DogCard({
    required this.dog,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final photo = safeImageProvider(dog.photoUrl);
    final ageLabel = dog.ageYears == 1 ? 'בן שנה' : 'בן ${dog.ageYears} שנים';
    final sizeLabel = kDogSizeLabels[dog.size] ?? dog.size;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFFF3F4F6),
                backgroundImage: photo,
                child: photo == null
                    ? const Icon(Icons.pets_rounded,
                        color: Color(0xFF6366F1), size: 28)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dog.name.isEmpty ? 'ללא שם' : dog.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (dog.isVaccinated)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(start: 4),
                            child: Icon(Icons.verified_rounded,
                                size: 18, color: Color(0xFF10B981)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [dog.breed, ageLabel, sizeLabel]
                          .where((s) => s.trim().isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dog.allergies.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: Color(0xFFEF4444)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'אלרגיות: ${dog.allergies.join(", ")}',
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFF9CA3AF)),
                onPressed: onDelete,
                tooltip: 'מחק',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
