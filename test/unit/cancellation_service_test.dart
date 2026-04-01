import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:anyskill_app/services/cancellation_policy_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tests for CancellationPolicyService — all public methods
//
// Run:  flutter test test/unit/cancellation_service_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('freeHours', () {
    test('flexible = 4 hours', () {
      expect(CancellationPolicyService.freeHours('flexible'), 4);
    });
    test('moderate = 24 hours', () {
      expect(CancellationPolicyService.freeHours('moderate'), 24);
    });
    test('strict = 48 hours', () {
      expect(CancellationPolicyService.freeHours('strict'), 48);
    });
    test('unknown defaults to flexible (4)', () {
      expect(CancellationPolicyService.freeHours('unknown'), 4);
    });
  });

  group('label', () {
    test('flexible → גמישה', () {
      expect(CancellationPolicyService.label('flexible'), 'גמישה');
    });
    test('moderate → בינונית', () {
      expect(CancellationPolicyService.label('moderate'), 'בינונית');
    });
    test('strict → קפדנית', () {
      expect(CancellationPolicyService.label('strict'), 'קפדנית');
    });
    test('unknown → גמישה', () {
      expect(CancellationPolicyService.label('xyz'), 'גמישה');
    });
  });

  group('description', () {
    test('flexible mentions 4 שעות', () {
      expect(CancellationPolicyService.description('flexible'), contains('4 שעות'));
    });
    test('moderate mentions 24 שעות', () {
      expect(CancellationPolicyService.description('moderate'), contains('24 שעות'));
    });
    test('strict mentions 48 שעות and 100%', () {
      final d = CancellationPolicyService.description('strict');
      expect(d, contains('48 שעות'));
      expect(d, contains('100%'));
    });
  });

  group('penaltyFraction', () {
    test('flexible = 50%', () {
      expect(CancellationPolicyService.penaltyFraction('flexible'), 0.5);
    });
    test('moderate = 50%', () {
      expect(CancellationPolicyService.penaltyFraction('moderate'), 0.5);
    });
    test('strict = 100%', () {
      expect(CancellationPolicyService.penaltyFraction('strict'), 1.0);
    });
  });

  group('deadline', () {
    test('calculates deadline correctly for flexible', () {
      final appt = DateTime(2026, 6, 15, 14, 0);
      final dl = CancellationPolicyService.deadline(
        policy: 'flexible',
        appointmentDate: appt,
        timeSlot: '14:00',
      );
      expect(dl, DateTime(2026, 6, 15, 10, 0)); // 14:00 - 4h
    });

    test('calculates deadline for moderate (24h)', () {
      final appt = DateTime(2026, 6, 15, 14, 0);
      final dl = CancellationPolicyService.deadline(
        policy: 'moderate',
        appointmentDate: appt,
        timeSlot: '14:00',
      );
      expect(dl, DateTime(2026, 6, 14, 14, 0)); // -24h = previous day
    });

    test('calculates deadline for strict (48h)', () {
      final appt = DateTime(2026, 6, 15, 10, 0);
      final dl = CancellationPolicyService.deadline(
        policy: 'strict',
        appointmentDate: appt,
        timeSlot: '10:00',
      );
      expect(dl, DateTime(2026, 6, 13, 10, 0)); // -48h = 2 days before
    });

    test('returns null for null appointmentDate', () {
      final dl = CancellationPolicyService.deadline(
        policy: 'flexible',
        appointmentDate: null,
        timeSlot: '10:00',
      );
      expect(dl, isNull);
    });

    test('handles null timeSlot (defaults to midnight)', () {
      final appt = DateTime(2026, 6, 15);
      final dl = CancellationPolicyService.deadline(
        policy: 'flexible',
        appointmentDate: appt,
        timeSlot: null,
      );
      // Midnight - 4h = previous day 20:00
      expect(dl, DateTime(2026, 6, 14, 20, 0));
    });

    test('handles malformed timeSlot', () {
      final appt = DateTime(2026, 6, 15);
      final dl = CancellationPolicyService.deadline(
        policy: 'flexible',
        appointmentDate: appt,
        timeSlot: 'invalid',
      );
      // Falls back to 0:0 then -4h
      expect(dl, DateTime(2026, 6, 14, 20, 0));
    });
  });

  group('penaltyAmountFor', () {
    test('returns 0 when within free window', () {
      // Deadline is in the future → no penalty
      final job = {
        'cancellationPolicy': 'flexible',
        'totalAmount': 200.0,
        'cancellationDeadline': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 5)),
        ),
      };
      expect(CancellationPolicyService.penaltyAmountFor(job), 0.0);
    });

    test('returns penalty after deadline (flexible 50%)', () {
      final job = {
        'cancellationPolicy': 'flexible',
        'totalAmount': 200.0,
        'cancellationDeadline': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
      };
      expect(CancellationPolicyService.penaltyAmountFor(job), 100.0);
    });

    test('returns full penalty after deadline (strict 100%)', () {
      final job = {
        'cancellationPolicy': 'strict',
        'totalAmount': 200.0,
        'cancellationDeadline': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
      };
      expect(CancellationPolicyService.penaltyAmountFor(job), 200.0);
    });

    test('returns 0 when deadline is null', () {
      final job = {
        'cancellationPolicy': 'flexible',
        'totalAmount': 200.0,
        // no cancellationDeadline
      };
      expect(CancellationPolicyService.penaltyAmountFor(job), 0.0);
    });

    test('defaults to flexible when policy is missing', () {
      final job = {
        'totalAmount': 100.0,
        'cancellationDeadline': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
      };
      // flexible penalty = 50%
      expect(CancellationPolicyService.penaltyAmountFor(job), 50.0);
    });
  });

  group('kPolicies', () {
    test('contains exactly 3 policies', () {
      expect(CancellationPolicyService.kPolicies.length, 3);
      expect(CancellationPolicyService.kPolicies,
          ['flexible', 'moderate', 'strict']);
    });
  });
}
