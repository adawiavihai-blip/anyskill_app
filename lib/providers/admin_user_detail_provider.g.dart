// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_user_detail_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$userDetailHash() => r'f458acf022e9b6dd99ed67e0ec3c1a20c56c9178';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [userDetail].
@ProviderFor(userDetail)
const userDetailProvider = UserDetailFamily();

/// See also [userDetail].
class UserDetailFamily extends Family<AsyncValue<Map<String, dynamic>>> {
  /// See also [userDetail].
  const UserDetailFamily();

  /// See also [userDetail].
  UserDetailProvider call(String userId) {
    return UserDetailProvider(userId);
  }

  @override
  UserDetailProvider getProviderOverride(
    covariant UserDetailProvider provider,
  ) {
    return call(provider.userId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'userDetailProvider';
}

/// See also [userDetail].
class UserDetailProvider
    extends AutoDisposeStreamProvider<Map<String, dynamic>> {
  /// See also [userDetail].
  UserDetailProvider(String userId)
    : this._internal(
        (ref) => userDetail(ref as UserDetailRef, userId),
        from: userDetailProvider,
        name: r'userDetailProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$userDetailHash,
        dependencies: UserDetailFamily._dependencies,
        allTransitiveDependencies: UserDetailFamily._allTransitiveDependencies,
        userId: userId,
      );

  UserDetailProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final String userId;

  @override
  Override overrideWith(
    Stream<Map<String, dynamic>> Function(UserDetailRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UserDetailProvider._internal(
        (ref) => create(ref as UserDetailRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<Map<String, dynamic>> createElement() {
    return _UserDetailProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UserDetailProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UserDetailRef on AutoDisposeStreamProviderRef<Map<String, dynamic>> {
  /// The parameter `userId` of this provider.
  String get userId;
}

class _UserDetailProviderElement
    extends AutoDisposeStreamProviderElement<Map<String, dynamic>>
    with UserDetailRef {
  _UserDetailProviderElement(super.provider);

  @override
  String get userId => (origin as UserDetailProvider).userId;
}

String _$userTransactionsHash() => r'0b8a76a2d85cdba6f75f91b8a7778234627d5c23';

/// See also [userTransactions].
@ProviderFor(userTransactions)
const userTransactionsProvider = UserTransactionsFamily();

/// See also [userTransactions].
class UserTransactionsFamily
    extends Family<AsyncValue<List<Map<String, dynamic>>>> {
  /// See also [userTransactions].
  const UserTransactionsFamily();

  /// See also [userTransactions].
  UserTransactionsProvider call(String userId) {
    return UserTransactionsProvider(userId);
  }

  @override
  UserTransactionsProvider getProviderOverride(
    covariant UserTransactionsProvider provider,
  ) {
    return call(provider.userId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'userTransactionsProvider';
}

/// See also [userTransactions].
class UserTransactionsProvider
    extends AutoDisposeFutureProvider<List<Map<String, dynamic>>> {
  /// See also [userTransactions].
  UserTransactionsProvider(String userId)
    : this._internal(
        (ref) => userTransactions(ref as UserTransactionsRef, userId),
        from: userTransactionsProvider,
        name: r'userTransactionsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$userTransactionsHash,
        dependencies: UserTransactionsFamily._dependencies,
        allTransitiveDependencies:
            UserTransactionsFamily._allTransitiveDependencies,
        userId: userId,
      );

  UserTransactionsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final String userId;

  @override
  Override overrideWith(
    FutureOr<List<Map<String, dynamic>>> Function(UserTransactionsRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UserTransactionsProvider._internal(
        (ref) => create(ref as UserTransactionsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<Map<String, dynamic>>> createElement() {
    return _UserTransactionsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UserTransactionsProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UserTransactionsRef
    on AutoDisposeFutureProviderRef<List<Map<String, dynamic>>> {
  /// The parameter `userId` of this provider.
  String get userId;
}

class _UserTransactionsProviderElement
    extends AutoDisposeFutureProviderElement<List<Map<String, dynamic>>>
    with UserTransactionsRef {
  _UserTransactionsProviderElement(super.provider);

  @override
  String get userId => (origin as UserTransactionsProvider).userId;
}

String _$userJobsHash() => r'2f18c304ed38795d6b5470e31c44a315f40292b3';

/// See also [userJobs].
@ProviderFor(userJobs)
const userJobsProvider = UserJobsFamily();

/// See also [userJobs].
class UserJobsFamily extends Family<AsyncValue<List<Map<String, dynamic>>>> {
  /// See also [userJobs].
  const UserJobsFamily();

  /// See also [userJobs].
  UserJobsProvider call(String userId) {
    return UserJobsProvider(userId);
  }

  @override
  UserJobsProvider getProviderOverride(covariant UserJobsProvider provider) {
    return call(provider.userId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'userJobsProvider';
}

/// See also [userJobs].
class UserJobsProvider
    extends AutoDisposeFutureProvider<List<Map<String, dynamic>>> {
  /// See also [userJobs].
  UserJobsProvider(String userId)
    : this._internal(
        (ref) => userJobs(ref as UserJobsRef, userId),
        from: userJobsProvider,
        name: r'userJobsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$userJobsHash,
        dependencies: UserJobsFamily._dependencies,
        allTransitiveDependencies: UserJobsFamily._allTransitiveDependencies,
        userId: userId,
      );

  UserJobsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final String userId;

  @override
  Override overrideWith(
    FutureOr<List<Map<String, dynamic>>> Function(UserJobsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UserJobsProvider._internal(
        (ref) => create(ref as UserJobsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<Map<String, dynamic>>> createElement() {
    return _UserJobsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UserJobsProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UserJobsRef on AutoDisposeFutureProviderRef<List<Map<String, dynamic>>> {
  /// The parameter `userId` of this provider.
  String get userId;
}

class _UserJobsProviderElement
    extends AutoDisposeFutureProviderElement<List<Map<String, dynamic>>>
    with UserJobsRef {
  _UserJobsProviderElement(super.provider);

  @override
  String get userId => (origin as UserJobsProvider).userId;
}

String _$userReviewsHash() => r'349632d69c8488525718c14dae15d6c717eaac6c';

/// See also [userReviews].
@ProviderFor(userReviews)
const userReviewsProvider = UserReviewsFamily();

/// See also [userReviews].
class UserReviewsFamily extends Family<AsyncValue<List<Map<String, dynamic>>>> {
  /// See also [userReviews].
  const UserReviewsFamily();

  /// See also [userReviews].
  UserReviewsProvider call(String userId) {
    return UserReviewsProvider(userId);
  }

  @override
  UserReviewsProvider getProviderOverride(
    covariant UserReviewsProvider provider,
  ) {
    return call(provider.userId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'userReviewsProvider';
}

/// See also [userReviews].
class UserReviewsProvider
    extends AutoDisposeFutureProvider<List<Map<String, dynamic>>> {
  /// See also [userReviews].
  UserReviewsProvider(String userId)
    : this._internal(
        (ref) => userReviews(ref as UserReviewsRef, userId),
        from: userReviewsProvider,
        name: r'userReviewsProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$userReviewsHash,
        dependencies: UserReviewsFamily._dependencies,
        allTransitiveDependencies: UserReviewsFamily._allTransitiveDependencies,
        userId: userId,
      );

  UserReviewsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final String userId;

  @override
  Override overrideWith(
    FutureOr<List<Map<String, dynamic>>> Function(UserReviewsRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UserReviewsProvider._internal(
        (ref) => create(ref as UserReviewsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<Map<String, dynamic>>> createElement() {
    return _UserReviewsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UserReviewsProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UserReviewsRef
    on AutoDisposeFutureProviderRef<List<Map<String, dynamic>>> {
  /// The parameter `userId` of this provider.
  String get userId;
}

class _UserReviewsProviderElement
    extends AutoDisposeFutureProviderElement<List<Map<String, dynamic>>>
    with UserReviewsRef {
  _UserReviewsProviderElement(super.provider);

  @override
  String get userId => (origin as UserReviewsProvider).userId;
}

String _$userAuditLogHash() => r'16a9519385138bde4e2f8aac7de79ef076217b60';

/// See also [userAuditLog].
@ProviderFor(userAuditLog)
const userAuditLogProvider = UserAuditLogFamily();

/// See also [userAuditLog].
class UserAuditLogFamily
    extends Family<AsyncValue<List<Map<String, dynamic>>>> {
  /// See also [userAuditLog].
  const UserAuditLogFamily();

  /// See also [userAuditLog].
  UserAuditLogProvider call(String userId) {
    return UserAuditLogProvider(userId);
  }

  @override
  UserAuditLogProvider getProviderOverride(
    covariant UserAuditLogProvider provider,
  ) {
    return call(provider.userId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'userAuditLogProvider';
}

/// See also [userAuditLog].
class UserAuditLogProvider
    extends AutoDisposeStreamProvider<List<Map<String, dynamic>>> {
  /// See also [userAuditLog].
  UserAuditLogProvider(String userId)
    : this._internal(
        (ref) => userAuditLog(ref as UserAuditLogRef, userId),
        from: userAuditLogProvider,
        name: r'userAuditLogProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$userAuditLogHash,
        dependencies: UserAuditLogFamily._dependencies,
        allTransitiveDependencies:
            UserAuditLogFamily._allTransitiveDependencies,
        userId: userId,
      );

  UserAuditLogProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final String userId;

  @override
  Override overrideWith(
    Stream<List<Map<String, dynamic>>> Function(UserAuditLogRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UserAuditLogProvider._internal(
        (ref) => create(ref as UserAuditLogRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<Map<String, dynamic>>> createElement() {
    return _UserAuditLogProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UserAuditLogProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UserAuditLogRef
    on AutoDisposeStreamProviderRef<List<Map<String, dynamic>>> {
  /// The parameter `userId` of this provider.
  String get userId;
}

class _UserAuditLogProviderElement
    extends AutoDisposeStreamProviderElement<List<Map<String, dynamic>>>
    with UserAuditLogRef {
  _UserAuditLogProviderElement(super.provider);

  @override
  String get userId => (origin as UserAuditLogProvider).userId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
