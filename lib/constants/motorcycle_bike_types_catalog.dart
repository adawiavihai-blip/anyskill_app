// Motorcycle bike-types catalog — offline fallback + initial seed.
//
// The LIVE source of truth is the Firestore collection
// `motorcycle_bike_types/{id}` (admin-editable via the dedicated admin tab).
// This list is a defensive fallback when Firestore is offline AND the seed
// the admin tab uses on first run.
//
// Image URLs are Unsplash defaults — admins can override per-bike-type via
// upload, system library, stock search, or external URL.
class MotorcycleBikeType {
  /// Stable id — also used as the Firestore doc id for seeded entries.
  final String id;
  /// Display name (Hebrew).
  final String name;
  /// English fallback (used by the admin tab + analytics).
  final String nameEn;
  /// Image URL (Unsplash default OR custom Storage URL).
  final String imageUrl;
  /// Whether the bike type is currently visible to providers + customers.
  final bool active;

  const MotorcycleBikeType({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.imageUrl,
    this.active = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'nameEn': nameEn,
        'imageUrl': imageUrl,
        'active': active,
      };

  factory MotorcycleBikeType.fromMap(Map<String, dynamic> m) =>
      MotorcycleBikeType(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        nameEn: m['nameEn'] as String? ?? '',
        imageUrl: m['imageUrl'] as String? ?? '',
        active: m['active'] is bool ? m['active'] as bool : true,
      );

  MotorcycleBikeType copyWith({
    String? name,
    String? nameEn,
    String? imageUrl,
    bool? active,
  }) =>
      MotorcycleBikeType(
        id: id,
        name: name ?? this.name,
        nameEn: nameEn ?? this.nameEn,
        imageUrl: imageUrl ?? this.imageUrl,
        active: active ?? this.active,
      );
}

/// 6 default bike types matching `motorcycleTowDefaults.js` from the spec.
const List<MotorcycleBikeType> kMotorcycleBikeTypesFallback = [
  MotorcycleBikeType(
    id: 'sport',
    name: 'ספורט',
    nameEn: 'Sport',
    imageUrl:
        'https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=600&h=450&fit=crop',
  ),
  MotorcycleBikeType(
    id: 'cruiser',
    name: 'קרוזר',
    nameEn: 'Cruiser',
    imageUrl:
        'https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=600&h=450&fit=crop',
  ),
  MotorcycleBikeType(
    id: 'adventure',
    name: 'אדוונצ\'ר',
    nameEn: 'Adventure',
    imageUrl:
        'https://images.unsplash.com/photo-1599819811279-d5ad9cccf838?w=600&h=450&fit=crop',
  ),
  MotorcycleBikeType(
    id: 'scooter',
    name: 'קטנוע',
    nameEn: 'Scooter',
    imageUrl:
        'https://images.unsplash.com/photo-1591216105232-d23bea36b827?w=600&h=450&fit=crop',
  ),
  MotorcycleBikeType(
    id: 'offroad',
    name: 'אופנועי שטח',
    nameEn: 'Off-road',
    imageUrl:
        'https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=600&h=450&fit=crop',
  ),
  MotorcycleBikeType(
    id: 'vintage',
    name: 'וינטג\'',
    nameEn: 'Vintage',
    imageUrl:
        'https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=600&h=450&fit=crop',
  ),
];

/// Helper for screens that need to look up a bike type by id from a mixed
/// source (live Firestore list + fallback list). Returns null when not found.
MotorcycleBikeType? findMotorcycleBikeType(
  String id,
  List<MotorcycleBikeType> live,
) {
  for (final t in live) {
    if (t.id == id) return t;
  }
  for (final t in kMotorcycleBikeTypesFallback) {
    if (t.id == id) return t;
  }
  return null;
}
