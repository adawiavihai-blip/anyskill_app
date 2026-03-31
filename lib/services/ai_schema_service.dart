/// AnySkill — AI Schema Generator Service
///
/// Calls the `generateServiceSchema` Cloud Function which uses Claude Haiku
/// to generate category-specific service schema fields with Hebrew labels.
///
/// Usage:
///   final schema = await AiSchemaService.generate('פנסיון לחיות מחמד');
///   // → [SchemaField(id: pricePerNight, label: מחיר ללילה, type: number, unit: ₪/ללילה), ...]
library;

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../widgets/category_specs_widget.dart';

class AiSchemaService {
  AiSchemaService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Generates a serviceSchema for the given category name using AI.
  ///
  /// Returns a list of [SchemaField] on success.
  /// Throws [AiSchemaException] with a Hebrew message on failure.
  static Future<List<SchemaField>> generate(String categoryName) async {
    if (categoryName.trim().length < 2) {
      throw AiSchemaException('שם קטגוריה חייב להכיל לפחות 2 תווים');
    }

    try {
      final callable = _fn.httpsCallable(
        'generateServiceSchema',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'categoryName': categoryName.trim(),
      });

      final data = result.data;
      final rawSchema = data['schema'] as List<dynamic>? ?? [];

      return rawSchema
          .whereType<Map<String, dynamic>>()
          .map((m) => SchemaField.fromMap(m))
          .where((f) => f.id.isNotEmpty && f.label.isNotEmpty)
          .toList();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[AiSchemaService] CF error: ${e.code} — ${e.message}');
      throw AiSchemaException(_friendlyMessage(e));
    } catch (e) {
      debugPrint('[AiSchemaService] error: $e');
      throw AiSchemaException('שגיאה ביצירת הסכמה: $e');
    }
  }

  static String _friendlyMessage(FirebaseFunctionsException e) {
    return switch (e.code) {
      'not-found' =>
        'הפונקציה "generateServiceSchema" לא נמצאת. '
            'הרץ: firebase deploy --only functions:generateServiceSchema',
      'permission-denied' => 'גישה מותרת רק למנהלים.',
      'unauthenticated' => 'יש להתחבר תחילה.',
      'deadline-exceeded' => 'הבקשה נמשכה יותר מדי. נסה שוב.',
      'internal' => e.message ?? 'שגיאה פנימית ב-AI.',
      _ => e.message ?? 'שגיאה לא צפויה.',
    };
  }
}

class AiSchemaException implements Exception {
  final String message;
  const AiSchemaException(this.message);
  @override
  String toString() => message;
}
