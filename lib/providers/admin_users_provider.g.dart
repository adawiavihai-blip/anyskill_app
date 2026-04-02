// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_users_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$adminUsersRepositoryHash() =>
    r'5fb969f3f0e0dcf8b475f9047a2a12f291d81200';

/// See also [adminUsersRepository].
@ProviderFor(adminUsersRepository)
final adminUsersRepositoryProvider = Provider<AdminUsersRepository>.internal(
  adminUsersRepository,
  name: r'adminUsersRepositoryProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$adminUsersRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AdminUsersRepositoryRef = ProviderRef<AdminUsersRepository>;
String _$adminUsersNotifierHash() =>
    r'084316a59e519c7cfdd9b4f247bd9b615e568140';

/// See also [AdminUsersNotifier].
@ProviderFor(AdminUsersNotifier)
final adminUsersNotifierProvider =
    AutoDisposeNotifierProvider<AdminUsersNotifier, AdminUsersState>.internal(
      AdminUsersNotifier.new,
      name: r'adminUsersNotifierProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$adminUsersNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AdminUsersNotifier = AutoDisposeNotifier<AdminUsersState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
