/// AnySkill — Dog Profile Model (Pet Stay Tracker v13.0.0)
///
/// Master profile that a customer builds once per dog and reuses across
/// bookings in the "בעלי חיים" category (sub-categories: פנסיון ביתי,
/// דוגווקר). At booking time the profile is snapshotted onto the job doc
/// (`jobs/{id}/petStay/data.dogSnapshot`) so provider-side edits by the
/// owner don't break in-flight stays.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Predefined personality tag keys. Labels render in Hebrew via
/// [kPersonalityLabels]. Stored as enum keys for i18n / analytics stability.
const List<String> kPersonalityKeys = [
  'friendly',
  'playful',
  'good_with_dogs',
  'good_with_cats',
  'good_with_kids',
  'calm_at_home',
  'energetic',
  'anxious',
  'leash_trained',
];

const Map<String, String> kPersonalityLabels = {
  'friendly': 'חברותי',
  'playful': 'אוהב משחק',
  'good_with_dogs': 'מסתדר עם כלבים',
  'good_with_cats': 'מסתדר עם חתולים',
  'good_with_kids': 'טוב עם ילדים',
  'calm_at_home': 'רגוע בבית',
  'energetic': 'אנרגטי',
  'anxious': 'חרדתי',
  'leash_trained': 'מאולף לרצועה',
};

const List<String> kDogSizes = ['small', 'medium', 'large'];
const Map<String, String> kDogSizeLabels = {
  'small': 'קטן',
  'medium': 'בינוני',
  'large': 'גדול',
};

const Map<String, String> kDogGenderLabels = {
  'male': 'זכר',
  'female': 'נקבה',
};

class Medication {
  final String name;
  final String dosage;
  final String frequency;
  final String instructions;

  const Medication({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.instructions,
  });

  factory Medication.empty() =>
      const Medication(name: '', dosage: '', frequency: '', instructions: '');

  factory Medication.fromMap(Map<String, dynamic> m) => Medication(
        name: (m['name'] ?? '') as String,
        dosage: (m['dosage'] ?? '') as String,
        frequency: (m['frequency'] ?? '') as String,
        instructions: (m['instructions'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'instructions': instructions,
      };

  Medication copyWith({
    String? name,
    String? dosage,
    String? frequency,
    String? instructions,
  }) =>
      Medication(
        name: name ?? this.name,
        dosage: dosage ?? this.dosage,
        frequency: frequency ?? this.frequency,
        instructions: instructions ?? this.instructions,
      );
}

class DogProfile {
  final String? id;

  // Identity
  final String name;
  final String breed;
  final int ageYears;
  final double weightKg;
  final String gender; // 'male' | 'female'
  final String size; // 'small' | 'medium' | 'large'
  final String? photoUrl;
  final String? vaccinationBookletUrl;
  final DateTime? birthDate;

  // Health toggles
  final bool isChipped;
  final bool isVaccinated;
  final bool isNeutered;

  // Personality
  final List<String> personality;
  final String personalityDescription;

  // Food & diet
  final String foodBrand;
  final String foodAmount;
  final List<String> allergies;
  final String allowedTreats;

  // Medications
  final List<Medication> medications;
  final String medicalNotes;

  // Emergency
  final String vetName;
  final String vetPhone;
  final String emergencyContact;
  final String emergencyPhone;

  // Routine
  final int feedingTimesPerDay;
  final int walksPerDay;
  final String bedtime; // "21:00"
  final String specialInstructions;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DogProfile({
    this.id,
    required this.name,
    required this.breed,
    required this.ageYears,
    required this.weightKg,
    required this.gender,
    required this.size,
    this.photoUrl,
    this.vaccinationBookletUrl,
    this.birthDate,
    required this.isChipped,
    required this.isVaccinated,
    required this.isNeutered,
    required this.personality,
    this.personalityDescription = '',
    required this.foodBrand,
    required this.foodAmount,
    required this.allergies,
    required this.allowedTreats,
    required this.medications,
    required this.medicalNotes,
    required this.vetName,
    required this.vetPhone,
    required this.emergencyContact,
    required this.emergencyPhone,
    required this.feedingTimesPerDay,
    required this.walksPerDay,
    required this.bedtime,
    required this.specialInstructions,
    this.createdAt,
    this.updatedAt,
  });

  factory DogProfile.empty() => const DogProfile(
        name: '',
        breed: '',
        ageYears: 1,
        weightKg: 10.0,
        gender: 'male',
        size: 'medium',
        isChipped: false,
        isVaccinated: false,
        isNeutered: false,
        personality: [],
        foodBrand: '',
        foodAmount: '',
        allergies: [],
        allowedTreats: '',
        medications: [],
        medicalNotes: '',
        vetName: '',
        vetPhone: '',
        emergencyContact: '',
        emergencyPhone: '',
        feedingTimesPerDay: 2,
        walksPerDay: 2,
        bedtime: '21:00',
        specialInstructions: '',
      );

  factory DogProfile.fromMap(String id, Map<String, dynamic> d) => DogProfile(
        id: id,
        name: (d['name'] ?? '') as String,
        breed: (d['breed'] ?? '') as String,
        ageYears: (d['ageYears'] as num?)?.toInt() ?? 0,
        weightKg: (d['weightKg'] as num?)?.toDouble() ?? 0.0,
        gender: (d['gender'] ?? 'male') as String,
        size: (d['size'] ?? 'medium') as String,
        photoUrl: d['photoUrl'] as String?,
        vaccinationBookletUrl: d['vaccinationBookletUrl'] as String?,
        birthDate: (d['birthDate'] as Timestamp?)?.toDate(),
        isChipped: (d['isChipped'] ?? false) as bool,
        isVaccinated: (d['isVaccinated'] ?? false) as bool,
        isNeutered: (d['isNeutered'] ?? false) as bool,
        personality: List<String>.from(d['personality'] ?? const []),
        personalityDescription: (d['personalityDescription'] ?? '') as String,
        foodBrand: (d['foodBrand'] ?? '') as String,
        foodAmount: (d['foodAmount'] ?? '') as String,
        allergies: List<String>.from(d['allergies'] ?? const []),
        allowedTreats: (d['allowedTreats'] ?? '') as String,
        medications: (d['medications'] as List? ?? const [])
            .map((e) => Medication.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        medicalNotes: (d['medicalNotes'] ?? '') as String,
        vetName: (d['vetName'] ?? '') as String,
        vetPhone: (d['vetPhone'] ?? '') as String,
        emergencyContact: (d['emergencyContact'] ?? '') as String,
        emergencyPhone: (d['emergencyPhone'] ?? '') as String,
        feedingTimesPerDay: (d['feedingTimesPerDay'] as num?)?.toInt() ?? 2,
        walksPerDay: (d['walksPerDay'] as num?)?.toInt() ?? 2,
        bedtime: (d['bedtime'] ?? '21:00') as String,
        specialInstructions: (d['specialInstructions'] ?? '') as String,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'breed': breed,
        'ageYears': ageYears,
        'weightKg': weightKg,
        'gender': gender,
        'size': size,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (vaccinationBookletUrl != null)
          'vaccinationBookletUrl': vaccinationBookletUrl,
        if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate!),
        'isChipped': isChipped,
        'isVaccinated': isVaccinated,
        'isNeutered': isNeutered,
        'personality': personality,
        'personalityDescription': personalityDescription,
        'foodBrand': foodBrand,
        'foodAmount': foodAmount,
        'allergies': allergies,
        'allowedTreats': allowedTreats,
        'medications': medications.map((m) => m.toMap()).toList(),
        'medicalNotes': medicalNotes,
        'vetName': vetName,
        'vetPhone': vetPhone,
        'emergencyContact': emergencyContact,
        'emergencyPhone': emergencyPhone,
        'feedingTimesPerDay': feedingTimesPerDay,
        'walksPerDay': walksPerDay,
        'bedtime': bedtime,
        'specialInstructions': specialInstructions,
      };

  DogProfile copyWith({
    String? id,
    String? name,
    String? breed,
    int? ageYears,
    double? weightKg,
    String? gender,
    String? size,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? vaccinationBookletUrl,
    bool clearVaccinationBookletUrl = false,
    DateTime? birthDate,
    bool clearBirthDate = false,
    bool? isChipped,
    bool? isVaccinated,
    bool? isNeutered,
    List<String>? personality,
    String? personalityDescription,
    String? foodBrand,
    String? foodAmount,
    List<String>? allergies,
    String? allowedTreats,
    List<Medication>? medications,
    String? medicalNotes,
    String? vetName,
    String? vetPhone,
    String? emergencyContact,
    String? emergencyPhone,
    int? feedingTimesPerDay,
    int? walksPerDay,
    String? bedtime,
    String? specialInstructions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      DogProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        breed: breed ?? this.breed,
        ageYears: ageYears ?? this.ageYears,
        weightKg: weightKg ?? this.weightKg,
        gender: gender ?? this.gender,
        size: size ?? this.size,
        photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
        vaccinationBookletUrl: clearVaccinationBookletUrl
            ? null
            : (vaccinationBookletUrl ?? this.vaccinationBookletUrl),
        birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
        isChipped: isChipped ?? this.isChipped,
        isVaccinated: isVaccinated ?? this.isVaccinated,
        isNeutered: isNeutered ?? this.isNeutered,
        personality: personality ?? this.personality,
        personalityDescription:
            personalityDescription ?? this.personalityDescription,
        foodBrand: foodBrand ?? this.foodBrand,
        foodAmount: foodAmount ?? this.foodAmount,
        allergies: allergies ?? this.allergies,
        allowedTreats: allowedTreats ?? this.allowedTreats,
        medications: medications ?? this.medications,
        medicalNotes: medicalNotes ?? this.medicalNotes,
        vetName: vetName ?? this.vetName,
        vetPhone: vetPhone ?? this.vetPhone,
        emergencyContact: emergencyContact ?? this.emergencyContact,
        emergencyPhone: emergencyPhone ?? this.emergencyPhone,
        feedingTimesPerDay: feedingTimesPerDay ?? this.feedingTimesPerDay,
        walksPerDay: walksPerDay ?? this.walksPerDay,
        bedtime: bedtime ?? this.bedtime,
        specialInstructions: specialInstructions ?? this.specialInstructions,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
