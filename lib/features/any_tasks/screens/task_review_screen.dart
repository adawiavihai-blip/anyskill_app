/// AnySkill — Task Review Screen (AnyTasks v14.2.0)
///
/// Airbnb-style dual rating applied to AnyTasks. Reuses the existing
/// `ReviewService` with `sourceCollection: 'any_tasks'` — the heavy
/// lifting (double-blind logic, 7-day lazy publish, rating recalcs)
/// all happens in the shared service. See CLAUDE.md §5.
///
/// Fields captured:
///   • Single overall rating (1-5 stars) — stored in ratingParams
///     as the only key ("overall") so the shared service averages to it
///   • Quick tags (multi-select chips, 6 options)
///   • Free-text review (≤ 500 chars)
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/review_service.dart';
import '../models/any_task.dart';
import '../theme/any_tasks_palette.dart';

/// Tag keys + Hebrew labels — used for both submit (store `key`) and
/// display (show `label`).
const List<(String, String)> kProviderTagOptions = [
  ('on_time', 'דייקן'),
  ('professional', 'מקצועי'),
  ('polite', 'אדיב'),
  ('clean', 'נקי ומסודר'),
  ('fast', 'מהיר'),
  ('good_comms', 'תקשורת טובה'),
];

const List<(String, String)> kClientTagOptions = [
  ('paid_fast', 'שילם מהר'),
  ('clear_brief', 'בריף ברור'),
  ('friendly', 'חברי'),
  ('fair', 'הוגן'),
  ('easy', 'קל לעבוד איתו'),
  ('responsive', 'מגיב מהר'),
];

class TaskReviewScreen extends StatefulWidget {
  final AnyTask task;

  /// True when the customer is reviewing the provider (default).
  /// False when the provider is reviewing the customer.
  final bool isClientReview;

  const TaskReviewScreen({
    super.key,
    required this.task,
    required this.isClientReview,
  });

  @override
  State<TaskReviewScreen> createState() => _TaskReviewScreenState();
}

class _TaskReviewScreenState extends State<TaskReviewScreen> {
  int _stars = 0;
  final _text = TextEditingController();
  final Set<String> _tags = <String>{};
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _starLabel {
    switch (_stars) {
      case 1: return 'גרוע';
      case 2: return 'לא טוב';
      case 3: return 'סביר';
      case 4: return 'טוב';
      case 5: return 'מעולה!';
      default: return '';
    }
  }

  Color get _starLabelColor {
    if (_stars <= 2) return TasksPalette.dangerRed;
    if (_stars == 3) return TasksPalette.amber;
    return TasksPalette.primaryGreenDark;
  }

  String get _revieweeName => widget.isClientReview
      ? widget.task.selectedProviderName ?? 'נותן השירות'
      : widget.task.clientName;

  String get _revieweeId => widget.isClientReview
      ? widget.task.selectedProviderId ?? ''
      : widget.task.clientId;

  List<(String, String)> get _tagOptions =>
      widget.isClientReview ? kProviderTagOptions : kClientTagOptions;

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('בחר דירוג כוכבים לפני שליחה'),
        backgroundColor: TasksPalette.dangerRed,
      ));
      return;
    }
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return;
    if (_revieweeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('אין מי לדרג — המשימה לא מלאה'),
        backgroundColor: TasksPalette.dangerRed,
      ));
      return;
    }

    setState(() => _submitting = true);
    try {
      final reviewerName = widget.isClientReview
          ? widget.task.clientName
          : widget.task.selectedProviderName ?? 'נותן שירות';
      await ReviewService.submitReview(
        jobId: widget.task.id!,
        sourceCollection: 'any_tasks',
        reviewerId: auth.uid,
        reviewerName: reviewerName,
        revieweeId: _revieweeId,
        isClientReview: widget.isClientReview,
        ratingParams: {'overall': _stars.toDouble()},
        publicComment: _text.text.trim(),
        privateAdminComment: '',
        reviewTags: _tags.toList(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('שגיאה בשליחה: $e'),
        backgroundColor: TasksPalette.dangerRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.bgPrimary,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardWhite,
        foregroundColor: TasksPalette.darkNavy,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.isClientReview ? 'דרג את נותן השירות' : 'דרג את הלקוח',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: _submitted ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Reviewee block ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rCard),
            boxShadow: TasksPalette.cardShadow,
          ),
          child: Row(
            children: [
              TasksAvatar(name: _revieweeName, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_revieweeName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: TasksPalette.darkNavy)),
                    const SizedBox(height: 4),
                    Text(widget.task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: TasksPalette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Stars ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rCard),
            boxShadow: TasksPalette.cardShadow,
          ),
          child: Column(
            children: [
              const Text('איך הייתה החוויה?',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TasksPalette.darkNavy)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final idx = i + 1;
                  final filled = _stars >= idx;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _stars = idx),
                      child: AnimatedScale(
                        scale: filled ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          filled ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 44,
                          color: filled
                              ? const Color(0xFFFFC107)
                              : TasksPalette.borderLight,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              AnimatedOpacity(
                opacity: _stars > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Text(_starLabel,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _starLabelColor)),
              ),
            ],
          ),
        ),

        // ── Tags (shown after star select) ──
        if (_stars > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TasksPalette.cardWhite,
              borderRadius: BorderRadius.circular(TasksPalette.rCard),
              boxShadow: TasksPalette.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('מה אפיין את השירות?',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.darkNavy)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tagOptions.map((t) {
                    final key = t.$1;
                    final label = t.$2;
                    final sel = _tags.contains(key);
                    return InkWell(
                      onTap: () => setState(() {
                        if (sel) {
                          _tags.remove(key);
                        } else {
                          _tags.add(key);
                        }
                      }),
                      borderRadius: BorderRadius.circular(TasksPalette.rChip),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? TasksPalette.primaryGreen
                                  .withValues(alpha: 0.08)
                              : TasksPalette.bgPrimary,
                          borderRadius:
                              BorderRadius.circular(TasksPalette.rChip),
                          border: Border.all(
                            color: sel
                                ? TasksPalette.primaryGreen
                                : TasksPalette.borderLight,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: sel
                                    ? TasksPalette.primaryGreenDark
                                    : TasksPalette.textSecondary)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],

        // ── Free-text review ──
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rCard),
            boxShadow: TasksPalette.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ביקורת חופשית (רשות)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TasksPalette.darkNavy)),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: widget.isClientReview
                      ? 'ספר לאחרים איך עבר השירות...'
                      : 'איך הייתה העבודה עם הלקוח?',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: TasksPalette.textMuted),
                  filled: true,
                  fillColor: TasksPalette.bgPrimary,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(TasksPalette.rInput),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),

        // ── Airbnb-style dual-rating banner ──
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TasksPalette.amberLight,
            borderRadius: BorderRadius.circular(TasksPalette.rInput),
          ),
          child: Row(
            children: [
              const Icon(Icons.stars_rounded,
                  color: TasksPalette.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'דירוג הדדי בסגנון Airbnb — גם $_revieweeName מדרג אותך. '
                  'הדירוגים נחשפים רק אחרי ששניכם סיימתם, כך שניכם כנים יותר.',
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: TasksPalette.amber),
                ),
              ),
            ],
          ),
        ),

        // ── Submit ──
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _submitting || _stars == 0 ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: TasksPalette.primaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: TasksPalette.borderLight,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TasksPalette.rButton)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('שלח דירוג',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 18),
            const Text('תודה על הדירוג!',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.darkNavy)),
            const SizedBox(height: 10),
            Text(
              'גם $_revieweeName ידרג אותך — הדירוג ההדדי יופיע לשניכם',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  color: TasksPalette.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TasksPalette.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(TasksPalette.rButton)),
                ),
                child: const Text('חזרה למשימות',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
