class FocusArea {
  final String id;
  final String nameHe;
  final String nameEn;

  const FocusArea({
    required this.id,
    required this.nameHe,
    required this.nameEn,
  });
}

const List<FocusArea> kMassageFocusAreas = [
  FocusArea(id: 'neck',       nameHe: 'צוואר',        nameEn: 'Neck'),
  FocusArea(id: 'shoulders',  nameHe: 'כתפיים',       nameEn: 'Shoulders'),
  FocusArea(id: 'upper_back', nameHe: 'גב עליון',     nameEn: 'Upper back'),
  FocusArea(id: 'lower_back', nameHe: 'גב תחתון',     nameEn: 'Lower back'),
  FocusArea(id: 'legs',       nameHe: 'רגליים',       nameEn: 'Legs'),
  FocusArea(id: 'arms',       nameHe: 'ידיים',        nameEn: 'Arms'),
  FocusArea(id: 'head',       nameHe: 'ראש',          nameEn: 'Head'),
  FocusArea(id: 'feet',       nameHe: 'כפות רגליים',  nameEn: 'Feet'),
];

FocusArea? findFocusArea(String id) {
  for (final a in kMassageFocusAreas) {
    if (a.id == id) return a;
  }
  return null;
}
