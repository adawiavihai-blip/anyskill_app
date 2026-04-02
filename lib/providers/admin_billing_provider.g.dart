// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_billing_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$adminBillingRepositoryHash() =>
    r'b0951c47ef2a73f06cbb1d66947d1094c3c1c22f';

/// See also [adminBillingRepository].
@ProviderFor(adminBillingRepository)
final adminBillingRepositoryProvider =
    Provider<AdminBillingRepository>.internal(
      adminBillingRepository,
      name: r'adminBillingRepositoryProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$adminBillingRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AdminBillingRepositoryRef = ProviderRef<AdminBillingRepository>;
String _$billingStatsHash() => r'4a8d67d973b6d776424b38ba66050db53e022149';

/// See also [billingStats].
@ProviderFor(billingStats)
final billingStatsProvider =
    AutoDisposeStreamProvider<Map<String, dynamic>>.internal(
      billingStats,
      name: r'billingStatsProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$billingStatsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BillingStatsRef = AutoDisposeStreamProviderRef<Map<String, dynamic>>;
String _$monthlyRevenueHash() => r'1cf35f71f0c8c59af4d1746a573790533adffb0e';

/// See also [monthlyRevenue].
@ProviderFor(monthlyRevenue)
final monthlyRevenueProvider = AutoDisposeFutureProvider<double>.internal(
  monthlyRevenue,
  name: r'monthlyRevenueProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$monthlyRevenueHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MonthlyRevenueRef = AutoDisposeFutureProviderRef<double>;
String _$billingActionsHash() => r'0a9f8e4b85bab832056b778c447a4ffdd05989f0';

/// See also [BillingActions].
@ProviderFor(BillingActions)
final billingActionsProvider =
    AutoDisposeNotifierProvider<BillingActions, bool>.internal(
      BillingActions.new,
      name: r'billingActionsProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$billingActionsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$BillingActions = AutoDisposeNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
