/// AnySkill — Dog Profile Card (Pet Stay Tracker v13.0.0)
///
/// Read-only display of a dog profile. Input is a `Map<String, dynamic>` —
/// typically the `dogSnapshot` field on a PetStay doc, but it also works
/// directly with a live DogProfile (just call `DogProfile.toMap()`).
///
/// Used on both Provider Pet Mode (Step 5) and Owner Pet Mode (Step 8).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/safe_image_provider.dart';
import '../models/dog_profile.dart';

class DogProfileCard extends StatelessWidget {
  final Map<String, dynamic> snapshot;

  const DogProfileCard({super.key, required this.snapshot});

  String _s(String key) => (snapshot[key] ?? '').toString();
  bool _b(String key) => (snapshot[key] ?? false) == true;
  int _i(String key) => (snapshot[key] as num?)?.toInt() ?? 0;
  double _d(String key) => (snapshot[key] as num?)?.toDouble() ?? 0.0;
  List<T> _l<T>(String key) =>
      List<T>.from((snapshot[key] as List?) ?? const []);

  @override
  Widget build(BuildContext context) {
    final name = _s('name');
    final breed = _s('breed');
    final age = _i('ageYears');
    final weight = _d('weightKg');
    final gender = _s('gender');
    final size = _s('size');
    final photo = safeImageProvider(snapshot['photoUrl'] as String?);
    final personality = _l<String>('personality');
    final allergies = _l<String>('allergies');
    // Permissive medications parse — Firestore SDKs vary in whether they
    // return nested Maps as Map<String,dynamic> or Map<Object?,Object?>.
    // `whereType<Map>() + Map.from()` works for both.
    final medications = (snapshot['medications'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5D98C), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(name, breed, age, weight, gender, size, photo),
          if (allergies.isNotEmpty) ...[
            const SizedBox(height: 14),
            _allergiesBanner(allergies),
          ],
          if (personality.isNotEmpty) ...[
            const SizedBox(height: 14),
            _personality(personality),
          ],
          const SizedBox(height: 14),
          _healthToggles(),
          if ((snapshot['vaccinationBookletUrl'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 14),
            _vaccinationBooklet(context),
          ],
          const SizedBox(height: 14),
          _foodSection(),
          if (medications.isNotEmpty) ...[
            const SizedBox(height: 14),
            _medicationsSection(medications),
          ],
          if (_s('medicalNotes').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _notesBlock('הערות רפואיות', _s('medicalNotes'),
                const Color(0xFFFAF5FF), const Color(0xFFA855F7)),
          ],
          const SizedBox(height: 14),
          _emergencySection(context),
          const SizedBox(height: 14),
          _routineSection(),
          if (_s('specialInstructions').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _notesBlock('הנחיות מיוחדות', _s('specialInstructions'),
                const Color(0xFFEFF6FF), const Color(0xFF3B82F6)),
          ],
        ],
      ),
    );
  }

  Widget _hero(
    String name,
    String breed,
    int age,
    double weight,
    String gender,
    String size,
    ImageProvider? photo,
  ) {
    final metaParts = <String>[];
    if (breed.isNotEmpty) metaParts.add(breed);
    if (age > 0) metaParts.add(age == 1 ? 'בן שנה' : 'בן $age שנים');
    if (weight > 0) metaParts.add('${weight.toStringAsFixed(0)} ק"ג');
    if (gender.isNotEmpty) metaParts.add(kDogGenderLabels[gender] ?? gender);
    if (size.isNotEmpty) metaParts.add(kDogSizeLabels[size] ?? size);

    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFFEEF2FF),
          backgroundImage: photo,
          child: photo == null
              ? const Icon(Icons.pets_rounded,
                  size: 36, color: Color(0xFF6366F1))
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'ללא שם' : name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              if (metaParts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  metaParts.join(' · '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _allergiesBanner(List<String> allergies) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFEF4444), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'אלרגיות',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allergies.join(', '),
                  style: const TextStyle(
                    color: Color(0xFF7F1D1D),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _personality(List<String> keys) {
    return _sectionWrap(
      title: 'אישיות',
      color: const Color(0xFFA855F7),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: keys
            .map((k) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD8B4FE)),
                  ),
                  child: Text(
                    kPersonalityLabels[k] ?? k,
                    style: const TextStyle(
                      color: Color(0xFF6B21A8),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _vaccinationBooklet(BuildContext context) {
    final url = snapshot['vaccinationBookletUrl'] as String? ?? '';
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('שגיאה בטעינת התמונה',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.open_in_new_rounded,
                      color: Colors.white),
                  onPressed: () =>
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                ),
              ),
            ],
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF10B981), width: 1.2),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.medical_services_outlined,
                      color: Color(0xFF10B981)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('פנקס חיסונים',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF065F46))),
                  SizedBox(height: 2),
                  Text('לחץ/י להגדלה',
                      style:
                          TextStyle(fontSize: 11, color: Color(0xFF065F46))),
                ],
              ),
            ),
            const Icon(Icons.zoom_in_rounded, color: Color(0xFF10B981)),
          ],
        ),
      ),
    );
  }

  Widget _healthToggles() {
    final items = <(String, bool, IconData)>[
      ('שבב', _b('isChipped'), Icons.memory_rounded),
      ('חיסונים', _b('isVaccinated'), Icons.vaccines_rounded),
      ('מסורס', _b('isNeutered'), Icons.medical_services_rounded),
    ];
    return Row(
      children: items
          .map((t) => Expanded(
                child: Container(
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.$2
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: t.$2
                          ? const Color(0xFF10B981)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        t.$3,
                        size: 18,
                        color: t.$2
                            ? const Color(0xFF10B981)
                            : const Color(0xFF9CA3AF),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.$1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: t.$2
                              ? const Color(0xFF065F46)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _foodSection() {
    final brand = _s('foodBrand');
    final amount = _s('foodAmount');
    final treats = _s('allowedTreats');
    if (brand.isEmpty && amount.isEmpty && treats.isEmpty) {
      return const SizedBox.shrink();
    }
    return _sectionWrap(
      title: 'אוכל',
      color: const Color(0xFFF59E0B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (brand.isNotEmpty) _kv('מותג', brand),
          if (amount.isNotEmpty) _kv('כמות', amount),
          if (treats.isNotEmpty) _kv('חטיפים מותרים', treats),
        ],
      ),
    );
  }

  Widget _medicationsSection(List<Map<String, dynamic>> meds) {
    return _sectionWrap(
      title: 'תרופות',
      color: const Color(0xFFEF4444),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: meds.map((m) {
          final name = (m['name'] ?? '') as String;
          final dosage = (m['dosage'] ?? '') as String;
          final freq = (m['frequency'] ?? '') as String;
          final inst = (m['instructions'] ?? '') as String;
          if (name.trim().isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7F1D1D),
                      fontSize: 14),
                ),
                if (dosage.isNotEmpty || freq.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [dosage, freq]
                        .where((s) => s.trim().isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                        color: Color(0xFF991B1B), fontSize: 12),
                  ),
                ],
                if (inst.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    inst,
                    style: const TextStyle(
                        color: Color(0xFF7F1D1D),
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emergencySection(BuildContext context) {
    final vetName = _s('vetName');
    final vetPhone = _s('vetPhone');
    final ecName = _s('emergencyContact');
    final ecPhone = _s('emergencyPhone');
    if ([vetName, vetPhone, ecName, ecPhone].every((s) => s.isEmpty)) {
      return const SizedBox.shrink();
    }
    return _sectionWrap(
      title: 'אנשי קשר לחירום',
      color: const Color(0xFFEF4444),
      child: Column(
        children: [
          if (vetName.isNotEmpty || vetPhone.isNotEmpty)
            _contactRow(context, Icons.local_hospital_rounded, 'וטרינר',
                vetName, vetPhone),
          if (ecName.isNotEmpty || ecPhone.isNotEmpty)
            _contactRow(
                context, Icons.person_pin_rounded, 'איש קשר', ecName, ecPhone),
        ],
      ),
    );
  }

  Widget _contactRow(BuildContext context, IconData icon, String label,
      String name, String phone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label · ${name.isEmpty ? "—" : name}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                        fontSize: 13)),
                if (phone.isNotEmpty)
                  Text(phone,
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 12)),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone_rounded, color: Color(0xFF10B981)),
              onPressed: () async {
                final uri = Uri.parse('tel:$phone');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
        ],
      ),
    );
  }

  Widget _routineSection() {
    final meals = _i('feedingTimesPerDay');
    final walks = _i('walksPerDay');
    final bedtime = _s('bedtime');
    return _sectionWrap(
      title: 'שגרה יומית',
      color: const Color(0xFF3B82F6),
      child: Row(
        children: [
          Expanded(
              child: _stat(Icons.restaurant_rounded, 'ארוחות', '$meals',
                  const Color(0xFFF59E0B))),
          Expanded(
              child: _stat(Icons.directions_walk_rounded, 'הליכונים',
                  '$walks', const Color(0xFF10B981))),
          if (bedtime.isNotEmpty)
            Expanded(
                child: _stat(Icons.bedtime_rounded, 'שינה', bedtime,
                    const Color(0xFF6366F1))),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color color) {
    return Container(
      margin: const EdgeInsetsDirectional.only(end: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sectionWrap({
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _notesBlock(String title, String content, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 4),
          Text(content,
              style: const TextStyle(
                  color: Color(0xFF1A1A2E), fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(
                  color: Color(0xFF1A1A2E), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
