import 'package:flutter/material.dart';

/// Severity level of a Scale Alert. Drives badge color + icon in the UI.
enum ScaleAlertLevel { success, info, warning, critical }

extension ScaleAlertLevelX on ScaleAlertLevel {
  Color get color => switch (this) {
        ScaleAlertLevel.success => const Color(0xFF4ADE80),
        ScaleAlertLevel.info => const Color(0xFF60A5FA),
        ScaleAlertLevel.warning => const Color(0xFFFBBF24),
        ScaleAlertLevel.critical => const Color(0xFFF87171),
      };

  IconData get icon => switch (this) {
        ScaleAlertLevel.success => Icons.check_circle_outline_rounded,
        ScaleAlertLevel.info => Icons.info_outline_rounded,
        ScaleAlertLevel.warning => Icons.warning_amber_rounded,
        ScaleAlertLevel.critical => Icons.error_outline_rounded,
      };

  String get hebrewLabel => switch (this) {
        ScaleAlertLevel.success => 'תקין',
        ScaleAlertLevel.info => 'מידע',
        ScaleAlertLevel.warning => 'אזהרה',
        ScaleAlertLevel.critical => 'קריטי',
      };
}

/// A scaling trigger alert. Produced by `ScaleAlertEngine` against the latest
/// `PerformanceMetric` snapshot. Tells the admin which Milestone to activate
/// next and why.
class ScaleAlert {
  final String id;
  final ScaleAlertLevel level;
  final String title;
  final String message;
  final String? actionLabel;
  final int targetMilestone;
  final String? milestoneFile;
  final String? triggerDetail;

  const ScaleAlert({
    required this.id,
    required this.level,
    required this.title,
    required this.message,
    this.actionLabel,
    required this.targetMilestone,
    this.milestoneFile,
    this.triggerDetail,
  });
}
