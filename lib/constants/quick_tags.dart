/// Shared catalog of provider Quick Tags.
/// 'key'   — stored in Firestore as a string inside the `quickTags` array.
/// 'emoji' — displayed in the tag chip.
/// 'label' — Hebrew display text.
const List<Map<String, String>> kQuickTagCatalog = [
  {'key': 'home_service',     'emoji': '🏠', 'label': 'מגיע/ה עד הבית'},
  {'key': 'first_discount',   'emoji': '🎁', 'label': 'שיעור ראשון ב-50%'},
  {'key': 'pregnancy_safe',   'emoji': '🤰', 'label': 'מתאים להריון'},
  {'key': 'insured',          'emoji': '🛡️', 'label': 'מבוטח/ת'},
  {'key': 'online_available', 'emoji': '💻', 'label': 'זמין אונליין'},
  {'key': 'certified',        'emoji': '🎓', 'label': 'מוסמך/ת'},
  {'key': 'weekend',          'emoji': '📅', 'label': 'זמין בסופ״ש'},
  {'key': 'group_sessions',   'emoji': '👥', 'label': 'שיעורי קבוצה'},
  {'key': 'fast_delivery',    'emoji': '⚡', 'label': 'עבודה מהירה'},
  {'key': 'accessible',       'emoji': '♿', 'label': 'נגיש לנכים'},
];

/// Looks up label+emoji for [key]. Returns null if not found.
Map<String, String>? quickTagByKey(String key) {
  for (final t in kQuickTagCatalog) {
    if (t['key'] == key) return t;
  }
  return null;
}
