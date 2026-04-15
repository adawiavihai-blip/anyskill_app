/// AnySkill — Dog Profile Service (Pet Stay Tracker v13.0.0)
///
/// CRUD for `users/{ownerId}/dogProfiles/{dogId}` plus photo upload to
/// `dog_profiles/{ownerId}/{dogId}.jpg` in Firebase Storage.
///
/// Owner-only. Firestore rule enforces `request.auth.uid == ownerId`.
/// Providers receive the dog card via a snapshot on the job doc — they do
/// NOT read this subcollection (Step 3 wires the snapshot).
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/dog_profile.dart';

class DogProfileService {
  DogProfileService._();
  static final instance = DogProfileService._();

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _col(String ownerId) =>
      _db.collection('users').doc(ownerId).collection('dogProfiles');

  Stream<List<DogProfile>> streamForOwner(String ownerId) => _col(ownerId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => DogProfile.fromMap(d.id, d.data()))
          .toList());

  Future<DogProfile?> get(String ownerId, String dogId) async {
    final doc = await _col(ownerId).doc(dogId).get();
    if (!doc.exists) return null;
    return DogProfile.fromMap(doc.id, doc.data()!);
  }

  /// Creates a new dog profile. Returns the new `dogId`.
  Future<String> create(String ownerId, DogProfile profile) async {
    final ref = _col(ownerId).doc();
    await ref.set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(
    String ownerId,
    String dogId,
    DogProfile profile,
  ) async {
    await _col(ownerId).doc(dogId).set({
      ...profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes the profile doc + its photo from Storage (best effort).
  /// Any existing `jobs/*/petStay/data.dogSnapshot` is unaffected —
  /// that's a frozen copy by design.
  Future<void> delete(String ownerId, String dogId) async {
    await _col(ownerId).doc(dogId).delete();
    try {
      await _storage.ref('dog_profiles/$ownerId/$dogId.jpg').delete();
    } catch (_) {}
  }

  /// Uploads a compressed photo to `dog_profiles/{ownerId}/{dogId}.jpg`,
  /// writes `photoUrl` onto the profile doc, and returns the download URL.
  Future<String> uploadPhoto({
    required String ownerId,
    required String dogId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ref = _storage.ref('dog_profiles/$ownerId/$dogId.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    await _col(ownerId).doc(dogId).set({
      'photoUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return url;
  }

  /// Uploads vaccination booklet image to
  /// `dog_profiles/{ownerId}/{dogId}_vax.jpg`, writes `vaccinationBookletUrl`
  /// onto the profile doc, and returns the download URL.
  Future<String> uploadVaccinationBooklet({
    required String ownerId,
    required String dogId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ref = _storage.ref('dog_profiles/$ownerId/${dogId}_vax.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    await _col(ownerId).doc(dogId).set({
      'vaccinationBookletUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return url;
  }
}
