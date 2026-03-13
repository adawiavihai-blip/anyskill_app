import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CategoryService {
  static const Map<String, IconData> iconMap = {
    'build':                 Icons.build,
    'cleaning_services':     Icons.cleaning_services,
    'camera_alt':            Icons.camera_alt,
    'fitness_center':        Icons.fitness_center,
    'school':                Icons.school,
    'palette':               Icons.palette,
    'pets':                  Icons.pets,
    'restaurant':            Icons.restaurant,
    'local_hospital':        Icons.local_hospital,
    'music_note':            Icons.music_note,
    'computer':              Icons.computer,
    'car_repair':            Icons.car_repair,
    'landscape':             Icons.landscape,
    'home':                  Icons.home,
    'child_care':            Icons.child_care,
    'translate':             Icons.translate,
    'design_services':       Icons.design_services,
    'plumbing':              Icons.plumbing,
    'electrical_services':   Icons.electrical_services,
    'content_cut':           Icons.content_cut,
  };

  static IconData getIcon(String? iconName) =>
      iconMap[iconName] ?? Icons.work_outline;

  static Stream<List<Map<String, dynamic>>> stream() =>
      FirebaseFirestore.instance
          .collection('categories')
          .orderBy('order')
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList());

  /// Only top-level categories (parentId absent or empty string)
  static Stream<List<Map<String, dynamic>>> streamMainCategories() =>
      stream().map((cats) => cats
          .where((c) => (c['parentId'] as String? ?? '').isEmpty)
          .toList());

  /// Sub-categories belonging to a specific main category doc ID
  static Stream<List<Map<String, dynamic>>> streamSubCategories(String parentId) =>
      stream().map((cats) => cats
          .where((c) => c['parentId'] == parentId)
          .toList());
}
