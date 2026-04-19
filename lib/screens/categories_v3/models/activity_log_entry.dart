import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// One row in `admin_activity_log/{logId}`. Emitted by `logAdminAction` CF
/// after every admin write. Used by the Activity Log panel + Undo flow.
class ActivityLogEntry {
  ActivityLogEntry({
    required this.id,
    required this.adminUid,
    required this.adminName,
    required this.actionType,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.createdAt,
    this.payloadBefore = const <String, dynamic>{},
    this.payloadAfter = const <String, dynamic>{},
    this.isReversible = true,
    this.reversedAt,
    this.reversedBy,
  });

  final String id;
  final String adminUid;
  final String adminName;
  final ActivityActionType actionType;
  final ActivityTargetType targetType;
  final String targetId;
  final String targetName;
  final DateTime createdAt;
  final Map<String, dynamic> payloadBefore;
  final Map<String, dynamic> payloadAfter;
  final bool isReversible;
  final DateTime? reversedAt;
  final String? reversedBy;

  bool get isReversed => reversedAt != null;

  /// Pretty Hebrew verb derived from [actionType] — used in the panel feed
  /// (`<admin_name> <verb> <target_name>`).
  String get hebrewVerb {
    switch (actionType) {
      case ActivityActionType.create:
        return 'יצר/ה';
      case ActivityActionType.update:
        return 'עדכן/ה';
      case ActivityActionType.delete:
        return 'מחק/ה';
      case ActivityActionType.reorder:
        return 'סידר/ה מחדש';
      case ActivityActionType.pin:
        return 'קידם/ה';
      case ActivityActionType.unpin:
        return 'הוריד/ה קידום';
      case ActivityActionType.hide:
        return 'הסתיר/ה';
      case ActivityActionType.unhide:
        return 'חשף/ה';
      case ActivityActionType.imageUpdate:
        return 'החליף/ה תמונה';
      case ActivityActionType.bulkAction:
        return 'ביצע/ה פעולה גורפת על';
      case ActivityActionType.undo:
        return 'ביטל/ה פעולה על';
    }
  }

  /// Color dot in the Activity Log panel per spec §7.9.
  Color get dotColor {
    switch (actionType) {
      case ActivityActionType.create:
        return const Color(0xFF10B981); // green
      case ActivityActionType.update:
      case ActivityActionType.imageUpdate:
        return const Color(0xFF3B82F6); // blue
      case ActivityActionType.reorder:
      case ActivityActionType.pin:
      case ActivityActionType.unpin:
        return const Color(0xFFF59E0B); // amber
      case ActivityActionType.hide:
      case ActivityActionType.unhide:
        return const Color(0xFF8B5CF6); // purple
      case ActivityActionType.delete:
        return const Color(0xFFEF4444); // red
      case ActivityActionType.bulkAction:
        return const Color(0xFF6366F1); // indigo
      case ActivityActionType.undo:
        return const Color(0xFF6B7280); // grey
    }
  }

  factory ActivityLogEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['created_at'];
    final reversedTs = data['reversed_at'];
    return ActivityLogEntry(
      id: doc.id,
      adminUid: (data['admin_uid'] as String?) ?? '',
      adminName: (data['admin_name'] as String?) ?? 'אדמין',
      actionType: _parseAction(data['action_type'] as String?),
      targetType: _parseTarget(data['target_type'] as String?),
      targetId: (data['target_id'] as String?) ?? '',
      targetName: (data['target_name'] as String?) ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      payloadBefore: data['payload_before'] is Map
          ? Map<String, dynamic>.from(data['payload_before'] as Map)
          : const <String, dynamic>{},
      payloadAfter: data['payload_after'] is Map
          ? Map<String, dynamic>.from(data['payload_after'] as Map)
          : const <String, dynamic>{},
      isReversible: (data['is_reversible'] as bool?) ?? true,
      reversedAt: reversedTs is Timestamp ? reversedTs.toDate() : null,
      reversedBy: data['reversed_by'] as String?,
    );
  }

  static ActivityActionType _parseAction(String? raw) {
    switch (raw) {
      case 'create':
        return ActivityActionType.create;
      case 'update':
        return ActivityActionType.update;
      case 'delete':
        return ActivityActionType.delete;
      case 'reorder':
        return ActivityActionType.reorder;
      case 'pin':
        return ActivityActionType.pin;
      case 'unpin':
        return ActivityActionType.unpin;
      case 'hide':
        return ActivityActionType.hide;
      case 'unhide':
        return ActivityActionType.unhide;
      case 'image_update':
        return ActivityActionType.imageUpdate;
      case 'bulk_action':
        return ActivityActionType.bulkAction;
      case 'undo':
        return ActivityActionType.undo;
      default:
        return ActivityActionType.update;
    }
  }

  static ActivityTargetType _parseTarget(String? raw) {
    switch (raw) {
      case 'subcategory':
        return ActivityTargetType.subcategory;
      case 'banner':
        return ActivityTargetType.banner;
      case 'category':
      default:
        return ActivityTargetType.category;
    }
  }
}

enum ActivityActionType {
  create,
  update,
  delete,
  reorder,
  pin,
  unpin,
  hide,
  unhide,
  imageUpdate,
  bulkAction,
  undo,
}

extension ActivityActionTypeWire on ActivityActionType {
  String get wire {
    switch (this) {
      case ActivityActionType.create:
        return 'create';
      case ActivityActionType.update:
        return 'update';
      case ActivityActionType.delete:
        return 'delete';
      case ActivityActionType.reorder:
        return 'reorder';
      case ActivityActionType.pin:
        return 'pin';
      case ActivityActionType.unpin:
        return 'unpin';
      case ActivityActionType.hide:
        return 'hide';
      case ActivityActionType.unhide:
        return 'unhide';
      case ActivityActionType.imageUpdate:
        return 'image_update';
      case ActivityActionType.bulkAction:
        return 'bulk_action';
      case ActivityActionType.undo:
        return 'undo';
    }
  }
}

enum ActivityTargetType { category, subcategory, banner }

extension ActivityTargetTypeWire on ActivityTargetType {
  String get wire {
    switch (this) {
      case ActivityTargetType.subcategory:
        return 'subcategory';
      case ActivityTargetType.banner:
        return 'banner';
      case ActivityTargetType.category:
        return 'category';
    }
  }
}
