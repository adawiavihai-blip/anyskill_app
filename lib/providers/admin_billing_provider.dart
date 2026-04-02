import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../repositories/admin_billing_repository.dart';

part 'admin_billing_provider.g.dart';

// ── Repository provider (singleton) ──────────────────────────────────────────

@Riverpod(keepAlive: true)
AdminBillingRepository adminBillingRepository(AdminBillingRepositoryRef ref) {
  return AdminBillingRepository();
}

// ── Billing KPI stream (autoDispose — cleaned up when tab is closed) ─────────

@riverpod
Stream<Map<String, dynamic>> billingStats(BillingStatsRef ref) {
  final repo = ref.watch(adminBillingRepositoryProvider);
  return repo.watchBillingStats();
}

// ── Monthly revenue (one-shot, autoDispose) ──────────────────────────────────

@riverpod
Future<double> monthlyRevenue(MonthlyRevenueRef ref) {
  final repo = ref.read(adminBillingRepositoryProvider);
  return repo.fetchMonthlyRevenue();
}

// ── Billing actions notifier ─────────────────────────────────────────────────

@riverpod
class BillingActions extends _$BillingActions {
  @override
  bool build() => false; // isSaving

  AdminBillingRepository get _repo =>
      ref.read(adminBillingRepositoryProvider);

  Future<bool> saveBudgetSettings({
    double? budgetLimit,
    double? killSwitchLimit,
  }) async {
    state = true;
    try {
      await _repo.saveBudgetSettings(
        budgetLimit: budgetLimit,
        killSwitchLimit: killSwitchLimit,
      );
      state = false;
      return true;
    } catch (e) {
      state = false;
      debugPrint('BillingActions.save error: $e');
      return false;
    }
  }

  Future<void> toggleKillSwitch(bool newValue) {
    return _repo.toggleKillSwitch(newValue);
  }
}
