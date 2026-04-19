// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'categories_v3_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$categoriesV3ServiceHash() =>
    r'9aaf36a759e54d97ce42f616e8f3a4879afc4cdd';

/// See also [categoriesV3Service].
@ProviderFor(categoriesV3Service)
final categoriesV3ServiceProvider = Provider<CategoriesV3Service>.internal(
  categoriesV3Service,
  name: r'categoriesV3ServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$categoriesV3ServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CategoriesV3ServiceRef = ProviderRef<CategoriesV3Service>;
String _$activityLogServiceHash() =>
    r'19f84dfba7a14818a76d86fadcdafa9f00cb69d3';

/// See also [activityLogService].
@ProviderFor(activityLogService)
final activityLogServiceProvider = Provider<ActivityLogService>.internal(
  activityLogService,
  name: r'activityLogServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activityLogServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ActivityLogServiceRef = ProviderRef<ActivityLogService>;
String _$categoryAnalyticsServiceHash() =>
    r'1c7a839c398db3e8827370488824f5457cb55f9f';

/// See also [categoryAnalyticsService].
@ProviderFor(categoryAnalyticsService)
final categoryAnalyticsServiceProvider =
    Provider<CategoryAnalyticsService>.internal(
      categoryAnalyticsService,
      name: r'categoryAnalyticsServiceProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$categoryAnalyticsServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CategoryAnalyticsServiceRef = ProviderRef<CategoryAnalyticsService>;
String _$savedViewsServiceHash() => r'1b415727bc4fa6cac1b67a5cc73174b2be69ca6b';

/// See also [savedViewsService].
@ProviderFor(savedViewsService)
final savedViewsServiceProvider = Provider<SavedViewsService>.internal(
  savedViewsService,
  name: r'savedViewsServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$savedViewsServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SavedViewsServiceRef = ProviderRef<SavedViewsService>;
String _$commandPaletteServiceHash() =>
    r'92bac7859ac22d7a1959e3c5963415205e4f0348';

/// See also [commandPaletteService].
@ProviderFor(commandPaletteService)
final commandPaletteServiceProvider = Provider<CommandPaletteService>.internal(
  commandPaletteService,
  name: r'commandPaletteServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$commandPaletteServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CommandPaletteServiceRef = ProviderRef<CommandPaletteService>;
String _$selectionControllerHash() =>
    r'7a4224c1a6be1ae23b2805ea21c7fcdae3e63785';

/// See also [selectionController].
@ProviderFor(selectionController)
final selectionControllerProvider = Provider<SelectionController>.internal(
  selectionController,
  name: r'selectionControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$selectionControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SelectionControllerRef = ProviderRef<SelectionController>;
String _$categoriesV3StreamHash() =>
    r'f8fe671ef907a8d9e43f5ad6662c137655112b44';

/// See also [categoriesV3Stream].
@ProviderFor(categoriesV3Stream)
final categoriesV3StreamProvider =
    AutoDisposeStreamProvider<List<CategoryV3Model>>.internal(
      categoriesV3Stream,
      name: r'categoriesV3StreamProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$categoriesV3StreamHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CategoriesV3StreamRef =
    AutoDisposeStreamProviderRef<List<CategoryV3Model>>;
String _$activityLogStreamHash() => r'52a2d1e45c92c19245c40203ccc755e4c7b13c7a';

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

/// See also [activityLogStream].
@ProviderFor(activityLogStream)
const activityLogStreamProvider = ActivityLogStreamFamily();

/// See also [activityLogStream].
class ActivityLogStreamFamily
    extends Family<AsyncValue<List<ActivityLogEntry>>> {
  /// See also [activityLogStream].
  const ActivityLogStreamFamily();

  /// See also [activityLogStream].
  ActivityLogStreamProvider call({int limit = 50}) {
    return ActivityLogStreamProvider(limit: limit);
  }

  @override
  ActivityLogStreamProvider getProviderOverride(
    covariant ActivityLogStreamProvider provider,
  ) {
    return call(limit: provider.limit);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'activityLogStreamProvider';
}

/// See also [activityLogStream].
class ActivityLogStreamProvider
    extends AutoDisposeStreamProvider<List<ActivityLogEntry>> {
  /// See also [activityLogStream].
  ActivityLogStreamProvider({int limit = 50})
    : this._internal(
        (ref) => activityLogStream(ref as ActivityLogStreamRef, limit: limit),
        from: activityLogStreamProvider,
        name: r'activityLogStreamProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$activityLogStreamHash,
        dependencies: ActivityLogStreamFamily._dependencies,
        allTransitiveDependencies:
            ActivityLogStreamFamily._allTransitiveDependencies,
        limit: limit,
      );

  ActivityLogStreamProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.limit,
  }) : super.internal();

  final int limit;

  @override
  Override overrideWith(
    Stream<List<ActivityLogEntry>> Function(ActivityLogStreamRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ActivityLogStreamProvider._internal(
        (ref) => create(ref as ActivityLogStreamRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        limit: limit,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<ActivityLogEntry>> createElement() {
    return _ActivityLogStreamProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityLogStreamProvider && other.limit == limit;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, limit.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ActivityLogStreamRef
    on AutoDisposeStreamProviderRef<List<ActivityLogEntry>> {
  /// The parameter `limit` of this provider.
  int get limit;
}

class _ActivityLogStreamProviderElement
    extends AutoDisposeStreamProviderElement<List<ActivityLogEntry>>
    with ActivityLogStreamRef {
  _ActivityLogStreamProviderElement(super.provider);

  @override
  int get limit => (origin as ActivityLogStreamProvider).limit;
}

String _$savedViewsStreamHash() => r'915627671a42da6e630bb036e16f972365323f66';

/// See also [savedViewsStream].
@ProviderFor(savedViewsStream)
final savedViewsStreamProvider =
    AutoDisposeStreamProvider<List<SavedView>>.internal(
      savedViewsStream,
      name: r'savedViewsStreamProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$savedViewsStreamHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SavedViewsStreamRef = AutoDisposeStreamProviderRef<List<SavedView>>;
String _$filteredCategoriesV3Hash() =>
    r'852f281634bd6df60e0ad99081046873c56c4283';

/// Filter + sort the live category list per the current screen state. Pure
/// in-memory transform — no extra Firestore reads.
///
/// Copied from [filteredCategoriesV3].
@ProviderFor(filteredCategoriesV3)
final filteredCategoriesV3Provider =
    AutoDisposeProvider<List<CategoryV3Model>>.internal(
      filteredCategoriesV3,
      name: r'filteredCategoriesV3Provider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$filteredCategoriesV3Hash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FilteredCategoriesV3Ref = AutoDisposeProviderRef<List<CategoryV3Model>>;
String _$categoriesKpisHash() => r'9460c1925baf948ba05e324ed4d5e79c753c97a3';

/// KPIs derived from the live (unfiltered) list — top of the dashboard.
///
/// Copied from [categoriesKpis].
@ProviderFor(categoriesKpis)
final categoriesKpisProvider = AutoDisposeProvider<CategoriesKpis>.internal(
  categoriesKpis,
  name: r'categoriesKpisProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$categoriesKpisHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CategoriesKpisRef = AutoDisposeProviderRef<CategoriesKpis>;
String _$categoriesV3ControllerHash() =>
    r'61c9b9879c77be83643187da5c1eccd796e094e1';

/// The screen-level controller — Riverpod Notifier (new API, no deprecated
/// `Ref` typedefs). Exposes commands the UI calls without rebuilding on
/// every Firestore tick.
///
/// Copied from [CategoriesV3Controller].
@ProviderFor(CategoriesV3Controller)
final categoriesV3ControllerProvider =
    NotifierProvider<CategoriesV3Controller, CategoriesScreenState>.internal(
      CategoriesV3Controller.new,
      name: r'categoriesV3ControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$categoriesV3ControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$CategoriesV3Controller = Notifier<CategoriesScreenState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
