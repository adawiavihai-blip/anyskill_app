// Customer types the provider can choose to serve.
class CleaningCustomerTypeDef {
  final String id;
  final String nameHe;
  final String icon;

  const CleaningCustomerTypeDef({
    required this.id,
    required this.nameHe,
    required this.icon,
  });
}

const List<CleaningCustomerTypeDef> kCleaningCustomerTypes = [
  CleaningCustomerTypeDef(id: 'private', nameHe: 'פרטיים', icon: '👤'),
  CleaningCustomerTypeDef(id: 'business', nameHe: 'עסקים', icon: '🏢'),
  CleaningCustomerTypeDef(id: 'stores', nameHe: 'חנויות', icon: '🏬'),
  CleaningCustomerTypeDef(id: 'restaurants', nameHe: 'מסעדות', icon: '🍽️'),
];
