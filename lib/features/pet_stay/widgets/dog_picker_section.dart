/// AnySkill — Dog Picker Section (Pet Stay Tracker v13.0.0)
///
/// Stateless UI block embedded in the booking summary sheet on
/// `expert_profile_screen.dart` when the active service has
/// `walkTracking || dailyProof`. Renders one of three states:
///
///   1. Loading                 — spinner while we stream the user's dogs
///   2. Empty (no dogs yet)     — CTA "צור פרופיל ראשון" → opens builder
///   3. List of dogs            — radio-style selectable cards
///
/// Selection is reported up via [onChanged] so the parent can gate the
/// "אשר ושלם" button.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../utils/safe_image_provider.dart';
import '../models/dog_profile.dart';
import '../screens/dog_profile_builder_screen.dart';
import '../services/dog_profile_service.dart';

class DogPickerSection extends StatelessWidget {
  final DogProfile? selected;
  final ValueChanged<DogProfile?> onChanged;

  const DogPickerSection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<DogProfile>>(
      stream: DogProfileService.instance.streamForOwner(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _wrap(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          );
        }

        final dogs = snap.data ?? const [];

        if (dogs.isEmpty) {
          return _wrap(child: const _EmptyCta());
        }

        // If the previously-selected dog vanished (deleted), clear it.
        if (selected != null &&
            !dogs.any((d) => d.id != null && d.id == selected!.id)) {
          // Defer to next frame to avoid setState-during-build.
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onChanged(null));
        }

        return _wrap(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 10),
              for (final dog in dogs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DogTile(
                    dog: dog,
                    selected: selected?.id == dog.id,
                    onTap: () => onChanged(dog),
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _openBuilder(context),
                  icon: const Icon(Icons.add_rounded,
                      color: Color(0xFF6366F1)),
                  label: const Text(
                    'הוסף כלב חדש',
                    style: TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _wrap({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }

  void _openBuilder(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DogProfileBuilderScreen(),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.pets_rounded,
              color: Color(0xFF6366F1), size: 18),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'בחר את הכלב',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'הפרטים יישלחו לנותן השירות',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DogTile extends StatelessWidget {
  final DogProfile dog;
  final bool selected;
  final VoidCallback onTap;

  const _DogTile({
    required this.dog,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo = safeImageProvider(dog.photoUrl);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 14, 10),
        decoration: BoxDecoration(
          color:
              selected ? const Color(0xFFEEF2FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF6366F1)
                : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFEEF2FF),
              backgroundImage: photo,
              child: photo == null
                  ? const Icon(Icons.pets_rounded,
                      color: Color(0xFF6366F1), size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name.isEmpty ? 'ללא שם' : dog.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1A1A2E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dog.breed.isNotEmpty)
                    Text(
                      dog.breed,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? const Color(0xFF6366F1)
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF6366F1)
                      : const Color(0xFFD1D5DB),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCta extends StatelessWidget {
  const _EmptyCta();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFBBF24)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFB45309), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'נדרש פרופיל כלב כדי להמשיך — נותן השירות צריך לדעת על אלרגיות, תרופות והרגלים.',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'בנה פרופיל ראשון',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DogProfileBuilderScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
