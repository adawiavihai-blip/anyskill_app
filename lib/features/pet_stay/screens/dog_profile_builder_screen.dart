/// AnySkill — Dog Profile Builder Screen (Pet Stay Tracker v13.0.0)
///
/// Owner-facing form to create or edit a [DogProfile]. 8 sections wrapped
/// in ExpansionTiles so the user isn't hit with a wall of inputs at once.
/// Photo upload goes to `dog_profiles/{ownerId}/{dogId}.jpg` via
/// [DogProfileService.uploadPhoto].
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../utils/image_compressor.dart';
import '../../../utils/safe_image_provider.dart';
import '../models/dog_profile.dart';
import '../services/dog_profile_service.dart';

class DogProfileBuilderScreen extends StatefulWidget {
  final DogProfile? existing;
  const DogProfileBuilderScreen({super.key, this.existing});

  @override
  State<DogProfileBuilderScreen> createState() =>
      _DogProfileBuilderScreenState();
}

class _DogProfileBuilderScreenState extends State<DogProfileBuilderScreen> {
  final _formKey = GlobalKey<FormState>();

  // Identity
  final _nameCtrl = TextEditingController();
  final _breedCtrl = TextEditingController();
  int _ageYears = 1;
  DateTime? _birthDate;
  double _weightKg = 10;
  String _gender = 'male';
  String _size = 'medium';
  String? _photoUrl;
  String? _vaccinationBookletUrl;
  bool _uploadingVax = false;
  String? _pendingDogId; // set after initial create so photo can attach

  // Health
  bool _isChipped = false;
  bool _isVaccinated = false;
  bool _isNeutered = false;

  // Personality
  final Set<String> _personality = {};
  final _personalityDescCtrl = TextEditingController();

  // Food
  final _foodBrandCtrl = TextEditingController();
  final _foodAmountCtrl = TextEditingController();
  final _allergyInputCtrl = TextEditingController();
  final List<String> _allergies = [];
  final _allowedTreatsCtrl = TextEditingController();

  // Medications
  final List<Medication> _medications = [];

  // Medical notes
  final _medicalNotesCtrl = TextEditingController();

  // Emergency
  final _vetNameCtrl = TextEditingController();
  final _vetPhoneCtrl = TextEditingController();
  final _emergencyContactCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  // Routine
  int _feedingTimesPerDay = 2;
  int _walksPerDay = 2;
  TimeOfDay _bedtime = const TimeOfDay(hour: 21, minute: 0);
  final _specialInstructionsCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    if (d == null) return;
    _pendingDogId = d.id;
    _nameCtrl.text = d.name;
    _breedCtrl.text = d.breed;
    _ageYears = d.ageYears;
    _weightKg = d.weightKg;
    _gender = d.gender;
    _size = d.size;
    _photoUrl = d.photoUrl;
    _vaccinationBookletUrl = d.vaccinationBookletUrl;
    _isChipped = d.isChipped;
    _isVaccinated = d.isVaccinated;
    _isNeutered = d.isNeutered;
    _personality.addAll(d.personality);
    _personalityDescCtrl.text = d.personalityDescription;
    _birthDate = d.birthDate;
    _foodBrandCtrl.text = d.foodBrand;
    _foodAmountCtrl.text = d.foodAmount;
    _allergies.addAll(d.allergies);
    _allowedTreatsCtrl.text = d.allowedTreats;
    _medications.addAll(d.medications);
    _medicalNotesCtrl.text = d.medicalNotes;
    _vetNameCtrl.text = d.vetName;
    _vetPhoneCtrl.text = d.vetPhone;
    _emergencyContactCtrl.text = d.emergencyContact;
    _emergencyPhoneCtrl.text = d.emergencyPhone;
    _feedingTimesPerDay = d.feedingTimesPerDay;
    _walksPerDay = d.walksPerDay;
    final parts = d.bedtime.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) _bedtime = TimeOfDay(hour: h, minute: m);
    }
    _specialInstructionsCtrl.text = d.specialInstructions;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _breedCtrl.dispose();
    _foodBrandCtrl.dispose();
    _foodAmountCtrl.dispose();
    _allergyInputCtrl.dispose();
    _allowedTreatsCtrl.dispose();
    _medicalNotesCtrl.dispose();
    _vetNameCtrl.dispose();
    _vetPhoneCtrl.dispose();
    _emergencyContactCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _specialInstructionsCtrl.dispose();
    _personalityDescCtrl.dispose();
    super.dispose();
  }

  String get _bedtimeStr =>
      '${_bedtime.hour.toString().padLeft(2, "0")}:${_bedtime.minute.toString().padLeft(2, "0")}';

  DogProfile _currentProfile() => DogProfile(
        id: _pendingDogId,
        name: _nameCtrl.text.trim(),
        breed: _breedCtrl.text.trim(),
        ageYears: _ageYears,
        weightKg: _weightKg,
        gender: _gender,
        size: _size,
        photoUrl: _photoUrl,
        vaccinationBookletUrl: _vaccinationBookletUrl,
        birthDate: _birthDate,
        isChipped: _isChipped,
        isVaccinated: _isVaccinated,
        isNeutered: _isNeutered,
        personality: _personality.toList(),
        personalityDescription: _personalityDescCtrl.text.trim(),
        foodBrand: _foodBrandCtrl.text.trim(),
        foodAmount: _foodAmountCtrl.text.trim(),
        allergies: List.of(_allergies),
        allowedTreats: _allowedTreatsCtrl.text.trim(),
        medications: List.of(_medications),
        medicalNotes: _medicalNotesCtrl.text.trim(),
        vetName: _vetNameCtrl.text.trim(),
        vetPhone: _vetPhoneCtrl.text.trim(),
        emergencyContact: _emergencyContactCtrl.text.trim(),
        emergencyPhone: _emergencyPhoneCtrl.text.trim(),
        feedingTimesPerDay: _feedingTimesPerDay,
        walksPerDay: _walksPerDay,
        bedtime: _bedtimeStr,
        specialInstructions: _specialInstructionsCtrl.text.trim(),
      );

  Future<void> _pickPhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Guard: we need a name to write a useful profile doc when the photo
    // upload forces the first-save. Without it, picking a photo and then
    // backing out creates an orphan doc with an empty name.
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש למלא שם לפני העלאת תמונה'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    final picked = await ImageCompressor.pick(ImagePreset.profileAvatar);
    if (picked == null) return;

    // Ensure the profile doc exists so we have a stable dogId for Storage.
    var dogId = _pendingDogId;
    if (dogId == null) {
      setState(() => _saving = true);
      try {
        dogId = await DogProfileService.instance.create(uid, _currentProfile());
        _pendingDogId = dogId;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאה ביצירה: $e')),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    setState(() => _saving = true);
    try {
      final url = await DogProfileService.instance.uploadPhoto(
        ownerId: uid,
        dogId: dogId,
        bytes: picked.bytes,
      );
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בהעלאת תמונה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickVaccinationBooklet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש למלא שם לפני העלאת פנקס חיסונים'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }
    final picked = await ImageCompressor.pick(ImagePreset.document);
    if (picked == null) return;

    var dogId = _pendingDogId;
    if (dogId == null) {
      setState(() => _uploadingVax = true);
      try {
        dogId = await DogProfileService.instance.create(uid, _currentProfile());
        _pendingDogId = dogId;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('שגיאה ביצירה: $e')),
          );
        }
        setState(() => _uploadingVax = false);
        return;
      }
    }

    setState(() => _uploadingVax = true);
    try {
      final url = await DogProfileService.instance.uploadVaccinationBooklet(
        ownerId: uid,
        dogId: dogId,
        bytes: picked.bytes,
      );
      if (mounted) setState(() => _vaccinationBookletUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בהעלאת פנקס חיסונים: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingVax = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final profile = _currentProfile();
      if (_pendingDogId == null) {
        await DogProfileService.instance.create(uid, profile);
      } else {
        await DogProfileService.instance.update(uid, _pendingDogId!, profile);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נשמר בהצלחה')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        centerTitle: true,
        title: Text(
          isEdit ? 'עריכת פרופיל כלב' : 'כלב חדש',
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                _buildPhoto(),
                const SizedBox(height: 16),
                _section(
                  icon: Icons.badge_outlined,
                  iconColor: const Color(0xFF6366F1),
                  title: 'זהות',
                  initiallyExpanded: true,
                  child: _identitySection(),
                ),
                _section(
                  icon: Icons.health_and_safety_outlined,
                  iconColor: const Color(0xFF10B981),
                  title: 'בריאות',
                  child: _healthSection(),
                ),
                _section(
                  icon: Icons.psychology_outlined,
                  iconColor: const Color(0xFFA855F7),
                  title: 'אישיות',
                  child: _personalitySection(),
                ),
                _section(
                  icon: Icons.restaurant_menu_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'אוכל ותזונה',
                  child: _foodSection(),
                ),
                _section(
                  icon: Icons.medication_outlined,
                  iconColor: const Color(0xFFEF4444),
                  title: 'תרופות',
                  child: _medicationsSection(),
                ),
                _section(
                  icon: Icons.notes_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'הערות רפואיות',
                  child: _medicalNotesSection(),
                ),
                _section(
                  icon: Icons.emergency_outlined,
                  iconColor: const Color(0xFFEF4444),
                  title: 'אנשי קשר לחירום',
                  child: _emergencySection(),
                ),
                _section(
                  icon: Icons.schedule_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'שגרה יומית',
                  child: _routineSection(),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _saving ? 'שומר...' : 'שמור',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Photo ────────────────────────────────────────────────────────────
  Widget _buildPhoto() {
    final photo = safeImageProvider(_photoUrl);
    return Center(
      child: InkWell(
        onTap: _saving ? null : _pickPhoto,
        borderRadius: BorderRadius.circular(64),
        child: Stack(
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEEF2FF),
                image: photo != null
                    ? DecorationImage(image: photo, fit: BoxFit.cover)
                    : null,
                border: Border.all(color: const Color(0xFF6366F1), width: 2),
              ),
              child: photo == null
                  ? const Icon(Icons.pets_rounded,
                      size: 56, color: Color(0xFF6366F1))
                  : null,
            ),
            PositionedDirectional(
              bottom: 0,
              end: 0,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF6366F1),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Generic section wrapper ──────────────────────────────────────────
  Widget _section({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding:
              const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xFF1A1A2E),
            ),
          ),
          children: [child],
        ),
      ),
    );
  }

  // ── Section 1: Identity ──────────────────────────────────────────────
  Widget _identitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textField(
          controller: _nameCtrl,
          label: 'שם',
          required: true,
        ),
        const SizedBox(height: 12),
        _textField(controller: _breedCtrl, label: 'גזע'),
        const SizedBox(height: 12),
        _birthDateTile(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _numberPicker(
                label: 'גיל (שנים)',
                value: _ageYears,
                min: 0,
                max: 25,
                onChanged: (v) => setState(() => _ageYears = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _weightSlider(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                label: 'מגדר',
                value: _gender,
                items: kDogGenderLabels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _gender = v ?? 'male'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown(
                label: 'גודל',
                value: _size,
                items: kDogSizes
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(kDogSizeLabels[s] ?? s),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _size = v ?? 'medium'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _weightSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            'משקל: ${_weightKg.toStringAsFixed(0)} ק"ג',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        Slider(
          value: _weightKg.clamp(1, 80),
          min: 1,
          max: 80,
          divisions: 79,
          activeColor: const Color(0xFF6366F1),
          onChanged: (v) => setState(() => _weightKg = v),
        ),
      ],
    );
  }

  // ── Section 2: Health ────────────────────────────────────────────────
  Widget _healthSection() {
    return Column(
      children: [
        _switchTile(
          title: 'שבב (מיקרו-צ\'יפ)',
          value: _isChipped,
          onChanged: (v) => setState(() => _isChipped = v),
        ),
        _switchTile(
          title: 'חיסונים בתוקף',
          value: _isVaccinated,
          onChanged: (v) => setState(() => _isVaccinated = v),
        ),
        _switchTile(
          title: 'מסורס/מעוקרת',
          value: _isNeutered,
          onChanged: (v) => setState(() => _isNeutered = v),
        ),
        const SizedBox(height: 14),
        _vaccinationBookletTile(),
      ],
    );
  }

  Widget _vaccinationBookletTile() {
    final hasBooklet =
        _vaccinationBookletUrl != null && _vaccinationBookletUrl!.isNotEmpty;
    return InkWell(
      onTap: _uploadingVax ? null : _pickVaccinationBooklet,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasBooklet
              ? const Color(0xFFECFDF5)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasBooklet
                ? const Color(0xFF10B981)
                : const Color(0xFFE5E7EB),
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            if (_uploadingVax)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else if (hasBooklet)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _vaccinationBookletUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.medical_services_outlined,
                      color: Color(0xFF10B981)),
                ),
              )
            else
              const Icon(Icons.medical_services_outlined,
                  color: Color(0xFF6366F1), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasBooklet ? 'פנקס חיסונים הועלה ✓' : 'פנקס חיסונים',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: hasBooklet
                          ? const Color(0xFF065F46)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasBooklet
                        ? 'לחיצה להחלפה'
                        : 'צלם/י את פנקס החיסונים — ייחשף רק לנותן השירות שבחרת',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280), height: 1.4),
                  ),
                ],
              ),
            ),
            Icon(
              hasBooklet ? Icons.swap_horiz_rounded : Icons.upload_rounded,
              color: hasBooklet
                  ? const Color(0xFF10B981)
                  : const Color(0xFF6366F1),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 3: Personality ───────────────────────────────────────────
  Widget _personalitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kPersonalityKeys.map((key) {
            final selected = _personality.contains(key);
            return FilterChip(
              label: Text(kPersonalityLabels[key] ?? key),
              selected: selected,
              selectedColor: const Color(0xFFEEF2FF),
              checkmarkColor: const Color(0xFF6366F1),
              side: BorderSide(
                color: selected
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFE5E7EB),
              ),
              labelStyle: TextStyle(
                color: selected
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF1A1A2E),
                fontWeight: FontWeight.w600,
              ),
              onSelected: (v) => setState(() {
                if (v) {
                  _personality.add(key);
                } else {
                  _personality.remove(key);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        _textField(
          controller: _personalityDescCtrl,
          label: 'ספרו קצת על הכלב — הרגלים, אהבות, פחדים…',
          maxLines: 4,
        ),
      ],
    );
  }

  // ── Birth date picker ───────────────────────────────────────────────
  Widget _birthDateTile() {
    final label = _birthDate == null
        ? 'תאריך לידה (אופציונלי)'
        : 'תאריך לידה: ${_birthDate!.day.toString().padLeft(2, "0")}/'
            '${_birthDate!.month.toString().padLeft(2, "0")}/'
            '${_birthDate!.year}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _birthDate ??
              DateTime(now.year - 2, now.month, now.day),
          firstDate: DateTime(now.year - 25),
          lastDate: now,
          helpText: 'בחר/י תאריך לידה',
        );
        if (picked != null) {
          setState(() {
            _birthDate = picked;
            final years = now.year - picked.year -
                ((now.month < picked.month ||
                        (now.month == picked.month &&
                            now.day < picked.day))
                    ? 1
                    : 0);
            _ageYears = years.clamp(0, 25);
          });
        }
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          const Icon(Icons.cake_rounded,
              size: 18, color: Color(0xFF6366F1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E))),
          ),
          if (_birthDate != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() => _birthDate = null),
              tooltip: 'נקה',
            )
          else
            const Icon(Icons.chevron_left_rounded,
                color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }

  // ── Section 4: Food ──────────────────────────────────────────────────
  Widget _foodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textField(controller: _foodBrandCtrl, label: 'מותג המזון'),
        const SizedBox(height: 12),
        _textField(
          controller: _foodAmountCtrl,
          label: 'כמות (למשל 250g בוקר + 200g ערב)',
        ),
        const SizedBox(height: 12),
        Text('אלרגיות',
            style: TextStyle(
                color: Colors.grey[700],
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: _allergyInputCtrl,
                label: 'הוסף אלרגיה (למשל: עוף)',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle,
                  color: Color(0xFF6366F1), size: 30),
              onPressed: () {
                final v = _allergyInputCtrl.text.trim();
                if (v.isEmpty) return;
                setState(() {
                  _allergies.add(v);
                  _allergyInputCtrl.clear();
                });
              },
            ),
          ],
        ),
        if (_allergies.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _allergies
                .map((a) => Chip(
                      label: Text(a),
                      backgroundColor: const Color(0xFFFEF2F2),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      labelStyle: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w600),
                      onDeleted: () => setState(() => _allergies.remove(a)),
                      deleteIconColor: const Color(0xFFEF4444),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
        _textField(
          controller: _allowedTreatsCtrl,
          label: 'חטיפים מותרים (למשל: גזר, תפוח)',
        ),
      ],
    );
  }

  // ── Section 5: Medications ───────────────────────────────────────────
  Widget _medicationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_medications.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'אין תרופות. לחץ + כדי להוסיף.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
        for (int i = 0; i < _medications.length; i++)
          _medRow(index: i),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded, color: Color(0xFF6366F1)),
            label: const Text(
              'הוסף תרופה',
              style: TextStyle(color: Color(0xFF6366F1)),
            ),
            onPressed: () =>
                setState(() => _medications.add(Medication.empty())),
          ),
        ),
      ],
    );
  }

  Widget _medRow({required int index}) {
    final med = _medications[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _inlineField(
                  initial: med.name,
                  label: 'שם התרופה',
                  onChanged: (v) => _medications[index] =
                      _medications[index].copyWith(name: v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444)),
                onPressed: () =>
                    setState(() => _medications.removeAt(index)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _inlineField(
                  initial: med.dosage,
                  label: 'מינון',
                  onChanged: (v) => _medications[index] =
                      _medications[index].copyWith(dosage: v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _inlineField(
                  initial: med.frequency,
                  label: 'תדירות',
                  onChanged: (v) => _medications[index] =
                      _medications[index].copyWith(frequency: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _inlineField(
            initial: med.instructions,
            label: 'הוראות נוספות',
            onChanged: (v) => _medications[index] =
                _medications[index].copyWith(instructions: v),
          ),
        ],
      ),
    );
  }

  // ── Section 6: Medical notes ─────────────────────────────────────────
  Widget _medicalNotesSection() {
    return TextFormField(
      controller: _medicalNotesCtrl,
      maxLines: 4,
      decoration: _inputDeco('הערות רפואיות כלליות'),
    );
  }

  // ── Section 7: Emergency ─────────────────────────────────────────────
  Widget _emergencySection() {
    return Column(
      children: [
        _textField(controller: _vetNameCtrl, label: 'שם הווטרינר'),
        const SizedBox(height: 12),
        _textField(
          controller: _vetPhoneCtrl,
          label: 'טלפון הווטרינר',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _textField(
            controller: _emergencyContactCtrl, label: 'איש קשר לחירום'),
        const SizedBox(height: 12),
        _textField(
          controller: _emergencyPhoneCtrl,
          label: 'טלפון לחירום',
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }

  // ── Section 8: Routine ───────────────────────────────────────────────
  Widget _routineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numberPicker(
          label: 'ארוחות ביום',
          value: _feedingTimesPerDay,
          min: 1,
          max: 6,
          onChanged: (v) => setState(() => _feedingTimesPerDay = v),
        ),
        const SizedBox(height: 12),
        _numberPicker(
          label: 'הליכונים ביום',
          value: _walksPerDay,
          min: 0,
          max: 6,
          onChanged: (v) => setState(() => _walksPerDay = v),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _bedtime,
            );
            if (picked != null) setState(() => _bedtime = picked);
          },
          child: Container(
            padding:
                const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bedtime_outlined, color: Color(0xFF6366F1)),
                const SizedBox(width: 10),
                const Text('שעת שינה',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(_bedtimeStr,
                    style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _specialInstructionsCtrl,
          maxLines: 3,
          decoration: _inputDeco('הנחיות מיוחדות'),
        ),
      ],
    );
  }

  // ── Reusable micro-widgets ───────────────────────────────────────────
  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool required = false,
    int? maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _inputDeco(label),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'שדה חובה' : null
          : null,
    );
  }

  Widget _inlineField({
    required String initial,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: initial,
      decoration: _inputDeco(label),
      onChanged: onChanged,
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      decoration: _inputDeco(label),
    );
  }

  Widget _numberPicker({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Color(0xFF6366F1)),
            onPressed:
                value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: Color(0xFF6366F1)),
            onPressed:
                value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: const Color(0xFF6366F1),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      value: value,
      onChanged: onChanged,
    );
  }
}
