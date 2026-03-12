import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';

class CategoriesSeeder {
  /// כותב את כל הקטגוריות מ-constants.dart לקולקציית categories ב-Firestore.
  /// בטוח להרצה כמה פעמים — משתמש ב-set (לא add), כך שלא יווצרו כפילויות.
  static Future<void> seed() async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    for (int i = 0; i < APP_CATEGORIES.length; i++) {
      final cat = APP_CATEGORIES[i];
      // ה-doc ID הוא שם הקטגוריה — מבטיח ייחודיות ופשטות בשאילתות
      final ref = firestore.collection('categories').doc(cat['name'] as String);
      batch.set(ref, {
        'name':     cat['name'],
        'img':      cat['img'],
        'iconName': cat['iconName'],
        'order':    i,
      });
    }

    await batch.commit();
  }
}
