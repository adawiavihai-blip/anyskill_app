// Default checklist templates used to seed a new provider's baseChecklist.
import '../models/cleaning_profile.dart';

List<CleaningChecklistCategory> defaultCleaningChecklist() {
  return const [
    CleaningChecklistCategory(
      categoryId: 'bedroom',
      categoryNameHe: 'חדר שינה',
      categoryIcon: '🛏️',
      tasks: [
        CleaningTask(
            id: 'bedroom_1',
            nameHe: 'החלפת מצעים + סידור מיטה',
            withPhoto: true),
        CleaningTask(
            id: 'bedroom_2',
            nameHe: 'שאיבת אבק + ניגוב משטחים'),
        CleaningTask(id: 'bedroom_3', nameHe: 'חלונות פנימיים'),
      ],
    ),
    CleaningChecklistCategory(
      categoryId: 'bathroom',
      categoryNameHe: 'חדר אמבטיה',
      categoryIcon: '🚿',
      tasks: [
        CleaningTask(
            id: 'bathroom_1',
            nameHe: 'ניקוי מקלחת + אסלה לעומק',
            withPhoto: true),
        CleaningTask(id: 'bathroom_2', nameHe: 'הסרת אבנית מברזים'),
      ],
    ),
    CleaningChecklistCategory(
      categoryId: 'kitchen',
      categoryNameHe: 'מטבח',
      categoryIcon: '🍽️',
      tasks: [
        CleaningTask(id: 'kitchen_1', nameHe: 'משטחי עבודה + כיורים'),
        CleaningTask(
            id: 'kitchen_2', nameHe: 'ניקוי תנור פנימי', addOnAmount: 40),
      ],
    ),
  ];
}

List<CleaningBusinessPackage> defaultBusinessPackages() {
  return const [
    CleaningBusinessPackage(
      id: 'package_4x',
      nameHe: '📅 4 ביקורים/חודש',
      visitsPerMonth: 4,
      monthlyPrice: 890,
      enabled: true,
    ),
    CleaningBusinessPackage(
      id: 'package_8x',
      nameHe: '🚀 8 ביקורים/חודש',
      visitsPerMonth: 8,
      monthlyPrice: 1690,
      enabled: false,
    ),
  ];
}

const List<String> kDefaultCleaningCities = [
  'תל אביב',
  'רמת גן',
  'גבעתיים',
  'הרצליה',
  'פתח תקווה',
  'ראשון לציון',
  'חולון',
  'בת ים',
  'רעננה',
  'כפר סבא',
  'נתניה',
  'חיפה',
  'ירושלים',
  'באר שבע',
];
