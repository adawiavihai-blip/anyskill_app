# AnySkill — Categories Admin Tab v3 (Pro) — Full Implementation Spec

> **Project:** AnySkill (anyskill-6fdf3) · **Stack:** Flutter (web + mobile) · Firebase · Firestore · Cloud Functions
> **Locale:** Hebrew RTL · **Module:** Admin → System → Categories tab redesign
> **Status:** Replaces existing `admin_categories_tab.dart`. Backwards compatible with current Firestore schema.

---

## 1. Goal

Replace the existing categories admin tab (a flat list with red/black/blue/orange action bars) with a **world-class category management workspace** matching the polish of Linear, Airbnb host dashboards, and Notion.

**Out of scope (DO NOT change):**
- Customer-facing home screen (`home_screen.dart`) — categories rendering stays identical
- Existing Firestore documents structure — we only **add** fields, never remove
- Category-Specific Modules (CSM) — they remain wired as-is
- Sub-category booking flows

**In scope:**
- Complete redesign of `admin_categories_tab.dart`
- New supporting widgets, services, and Cloud Functions
- New analytics fields (additive) on the categories collection
- Activity log collection (new)
- Saved views per admin user (new)

---

## 2. Files to Create / Modify

### 2.1 New files
```
lib/admin/categories_v3/
├── admin_categories_v3_tab.dart                     [main entry — replaces v1 tab]
├── widgets/
│   ├── category_row_card.dart                       [single category row with funnel + sparkline]
│   ├── subcategory_grid.dart                        [expanded sub-categories grid]
│   ├── subcategory_thumb.dart                       [single sub-category thumb (image + name + meta)]
│   ├── banner_row_card.dart                         [AnyTasks / נתינה מהלב promoted banner row]
│   ├── kpi_metrics_row.dart                         [5 KPI cards strip]
│   ├── toolbar_bar.dart                             [search + filter + sort + view switcher]
│   ├── bulk_actions_bar.dart                        [appears when selections > 0]
│   ├── keyboard_shortcuts_hint.dart                 [grey strip of shortcuts]
│   ├── sparkline_widget.dart                        [30-day mini line chart, custom painter]
│   ├── conversion_funnel_inline.dart                [views → clicks → orders inline display]
│   ├── coverage_chip.dart                           [🌍 X cities pill]
│   ├── health_score_bar.dart                        [progress bar + score 0-100]
│   ├── category_status_chips.dart                   [active / popular / hot / CSM / warning chips]
│   ├── activity_log_panel.dart                      [collapsible right-side history panel]
│   ├── command_palette_overlay.dart                 [⌘K modal with fuzzy search + actions]
│   ├── power_tools_footer.dart                      [refresh images / reset popularity / export / import]
│   └── empty_state_widget.dart                      [reusable empty state]
├── dialogs/
│   ├── add_category_dialog.dart                     [3-step wizard: details → image → sub-categories]
│   ├── edit_category_dialog.dart                    [5 tabs: details / image / subs / providers / stats]
│   ├── confirm_destructive_dialog.dart              [reusable confirm with type-to-delete]
│   └── saved_view_dialog.dart                       [save current filter combination]
├── models/
│   ├── category_v3_model.dart                       [extends existing CategoryModel with analytics]
│   ├── activity_log_entry.dart
│   ├── saved_view.dart
│   └── command_palette_action.dart
├── services/
│   ├── categories_v3_service.dart                   [CRUD + ordering + bulk ops]
│   ├── activity_log_service.dart                    [write/read/undo activity]
│   ├── category_analytics_service.dart              [reads aggregated metrics]
│   ├── command_palette_service.dart                 [fuzzy search + action dispatcher]
│   └── saved_views_service.dart                     [per-admin saved filter sets]
└── controllers/
    ├── categories_v3_controller.dart                [Provider/Riverpod state for the screen]
    └── selection_controller.dart                    [bulk selection state]
```

### 2.2 Files to modify
```
lib/admin/admin_screen.dart                          [swap v1 tab import → v3 tab import]
functions/index.js                                   [add 3 new Cloud Functions — see §6]
firestore.rules                                      [add rules for activity_log + admin_views collections]
firestore.indexes.json                               [add composite indexes — see §5]
```

### 2.3 DO NOT touch
- `home_screen.dart`
- `category_card_widget.dart` (the customer-facing one)
- `category_section_widget.dart`
- Any CSM block (`cleaning_settings_block.dart`, etc.)
- Existing `categories_service.dart` — leave untouched, the new service runs alongside

---

## 3. Firestore Schema Changes (Additive Only)

### 3.1 `categories/{categoryId}` — add fields
```typescript
{
  // ...all existing fields stay as-is...

  // NEW analytics cache (updated by Cloud Function every 15 min)
  analytics: {
    views_30d: number,            // total impressions in home tab
    clicks_30d: number,           // taps on the category card
    orders_30d: number,           // bookings completed
    revenue_30d: number,          // ILS gross
    ctr_30d: number,              // clicks / views
    growth_30d: number,           // % vs previous 30 days
    sparkline_30d: number[],      // array of 30 daily order counts (for the mini chart)
    coverage_cities: number,      // distinct cities where active providers exist
    active_providers: number,
    health_score: number,         // 0-100, computed by formula in §4
    last_updated: Timestamp,
  },

  // NEW admin metadata
  admin_meta: {
    is_pinned: boolean,           // shows in "מקודמות" section
    is_hidden: boolean,           // hidden from customer home
    last_edited_by: string,       // admin uid
    last_edited_at: Timestamp,
    last_edited_action: string,   // 'created' | 'image_changed' | 'reordered' | etc.
    notes: string,                // free-form admin notes (optional)
  },

  // NEW CSM linkage (read-only — informational)
  csm_module: string | null,      // 'cleaning' | 'massage' | 'delivery' | 'handyman' | 'pest_control' | null

  // NEW custom badges admin can set
  custom_tags: string[],          // ['🔥 חם', '🚀 צמיחה', etc.] — manual override
}
```

### 3.2 `categories/{categoryId}/subcategories/{subId}` — add fields
```typescript
{
  // ...existing fields...
  analytics: {
    orders_30d: number,
    revenue_30d: number,
    active_providers: number,
  },
  admin_meta: {
    last_edited_at: Timestamp,
    last_edited_by: string,
  },
}
```

### 3.3 NEW collection: `admin_activity_log/{logId}`
```typescript
{
  id: string,                     // auto
  admin_uid: string,
  admin_name: string,             // denormalized for display
  action_type: string,            // 'create' | 'update' | 'delete' | 'reorder' | 'pin' | 'hide' | 'image_update'
  target_type: string,            // 'category' | 'subcategory' | 'banner'
  target_id: string,
  target_name: string,            // denormalized name at time of action
  payload_before: object,         // snapshot for undo (only kept 30 days)
  payload_after: object,
  is_reversible: boolean,
  reversed_at: Timestamp | null,
  reversed_by: string | null,
  created_at: Timestamp,
}
```

### 3.4 NEW collection: `admin_saved_views/{viewId}`
```typescript
{
  id: string,
  admin_uid: string,
  name: string,                   // 'קטגוריות עם בעיות'
  filters: {
    status: string[],
    has_image: boolean | null,
    has_providers: boolean | null,
    is_csm: boolean | null,
    custom_query: string,
  },
  sort_by: string,
  view_mode: 'tree' | 'grid' | 'analytics',
  is_default: boolean,
  created_at: Timestamp,
}
```

### 3.5 NEW collection: `promoted_banners/{bannerId}`
This formalizes AnyTasks and נתינה מהלב as managed entities (currently they may be hardcoded).
```typescript
{
  id: string,
  type: string,                   // 'anytasks' | 'community' | 'custom'
  title: string,                  // 'AnyTasks', 'נתינה מהלב'
  subtitle: string,
  cta_label: string,              // 'פרסם משימה', '3 מתנדבים פעילים'
  icon: string,                   // emoji or storage url
  gradient_start: string,         // hex
  gradient_end: string,
  position: string,               // 'after_categories' | 'end_of_page' | 'top'
  display_order: number,
  is_active: boolean,
  link_target: string,            // route name
  analytics: {
    impressions_7d: number,
    clicks_7d: number,
    ctr_7d: number,
    sparkline_7d: number[],
  },
  admin_meta: { ... },
  created_at: Timestamp,
}
```

---

## 4. Health Score Formula

Computed in `category_analytics_service.dart` and cached in `analytics.health_score`:

```
score = round(
  (active_providers_score * 0.25) +
  (orders_score * 0.25) +
  (image_score * 0.10) +
  (rating_score * 0.15) +
  (growth_score * 0.15) +
  (coverage_score * 0.10)
)

where:
  active_providers_score = min(100, active_providers * 10)        // 10+ providers = full score
  orders_score = min(100, (orders_30d / target_orders) * 100)    // target_orders=200
  image_score = (has_main_image ? 60 : 0) + (sub_images_filled_pct * 0.4)
  rating_score = (avg_rating / 5) * 100
  growth_score = clamp(50 + growth_30d * 2, 0, 100)              // 0% growth = 50, 25% growth = 100
  coverage_score = min(100, coverage_cities * 8)                 // 12+ cities = full score
```

Color thresholds:
- `0-49`  → red (var(--color-text-danger))
- `50-74` → amber (var(--color-text-warning))
- `75-100` → green (var(--color-text-success))

---

## 5. Firestore Indexes (composite)

Add to `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "admin_activity_log",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "admin_uid", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "admin_activity_log",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "target_type", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "categories",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "admin_meta.is_hidden", "order": "ASCENDING" },
        { "fieldPath": "admin_meta.is_pinned", "order": "DESCENDING" },
        { "fieldPath": "display_order", "order": "ASCENDING" }
      ]
    }
  ]
}
```

---

## 6. Cloud Functions (functions/index.js)

Add three new functions. Use **Gemini 2.5 Flash Lite** for any AI work to stay consistent with the project's hybrid AI architecture (CLAUDE.md §12c, §31).

### 6.1 `updateCategoryAnalytics` — scheduled
```javascript
// Runs every 15 minutes
// For each category:
//   1. Aggregate views from `category_impressions` collection (last 30d)
//   2. Aggregate clicks from `category_clicks` collection
//   3. Aggregate orders + revenue from `bookings` where category_id matches
//   4. Compute sparkline_30d (array of 30 daily order counts)
//   5. Count distinct cities from active providers
//   6. Compute health_score using formula in §4
//   7. Write to categories/{id}/analytics
exports.updateCategoryAnalytics = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async (context) => { ... });
```

### 6.2 `logAdminAction` — callable
```javascript
// Called from client when admin makes a change
// Writes to admin_activity_log with before/after snapshot
exports.logAdminAction = functions.https.onCall(async (data, context) => {
  // Verify auth + admin role
  // Write log entry with payload_before, payload_after
});
```

### 6.3 `undoAdminAction` — callable
```javascript
// Reverts an action by re-applying payload_before
// Marks original log entry as reversed_at + reversed_by
// Creates a new log entry of type 'undo' linked to original
exports.undoAdminAction = functions.https.onCall(async (data, context) => { ... });
```

---

## 7. UI / UX Specification

> **Reference mockup:** see attached design (matches v3 Pro from chat). All measurements are mobile-first; scale up gracefully on web.

### 7.1 Layout structure (top to bottom)
1. **Top bar** — breadcrumb · sync status · title · version badge · ⌘K · history · export · + category
2. **5 KPI cards** — categories / sub-categories / missing images / no providers / in CSM
3. **Toolbar** — search · saved views select · sort select · view switcher (tree/grid/analytics)
4. **Keyboard shortcuts hint strip** (grey, dismissable, remembered in local storage)
5. **Bulk actions bar** (sticky, appears only when selections > 0)
6. **📌 Promoted/Banners section** (AnyTasks + נתינה מהלב + future custom)
7. **Categories list** (11 rows, drag-and-drop reorderable)
8. **+ Add new category** dashed button at bottom of list
9. **Activity Log panel** (collapsible, slides in from right)
10. **Power Tools footer** — refresh images / reset popularity / export JSON / import JSON

### 7.2 Visual tokens (Hebrew RTL)
- All padding/margin must respect RTL — use Flutter's `EdgeInsetsDirectional` everywhere
- Font: app default (Heebo/Rubik/etc. as currently configured)
- Border radius: `8px` for chips, `12px` for cards, `16px` for the main expanded panel
- Borders: `0.5px solid #00000026` (or `#FFFFFF26` in dark mode)
- Card hover: border color shifts to `#00000040`
- Animations: 150ms ease for expand/collapse, hover, and selection states
- Icons: prefer Lucide-style line icons (`lucide_icons` package) over Material when available; emoji allowed for visual variety in chips

### 7.3 Category row card (single row anatomy)
```
[checkbox] [⋮⋮ drag] [emoji avatar 40x40] [content area flex] [sparkline 60x28] [coverage chip] [health bar+score] [actions: 📌 ✎ ⋯ ▼]

content area =
  row 1: [name 13/500] [chip: status] [chip: popularity] [chip: CSM] [last edited text 10/400]
  row 2 (10/400 secondary): "12.4K צפיות → 3.2K קליקים → 284 הזמנות · 67 ספקים · ₪34.2K · ▲ 18%"
```

### 7.4 Sub-categories grid (expanded panel)
- Background: `var(--color-background-tertiary)` (or `#F5F5F0` in light mode)
- Grid: `repeat(auto-fill, minmax(110px, 1fr))` with `8px` gap
- Each thumb: square aspect, image fills, edit pencil top-left (RTL = visual top-right), name + provider count below
- "+ הוסף" dashed card at end
- Empty image: shows first letter of sub-category name on `var(--color-background-info)` with a `!` warning dot

### 7.5 Sparkline widget
- 60×28px custom painter
- Green stroke + 8% green fill if growth > 0
- Red stroke + 8% red fill if growth < 0
- Stroke width 1.5px
- Smooth Catmull-Rom interpolation between 30 daily points

### 7.6 Health score bar
- 50px wide, 4px tall track on `var(--color-background-tertiary)`
- Fill color by threshold (red/amber/green)
- Label: 2-digit number, weight 500, color matches fill

### 7.7 Bulk actions bar
- Slides up from bottom of viewport when `selectionCount > 0`
- Black background, white text
- Buttons: העבר להורה / הסתר / קדם / מחק (red destructive)
- "X נבחרו" + "ביטול בחירה" on right (RTL = visual left)

### 7.8 Command Palette (⌘K)
- Modal overlay, centered, `480px` wide max
- Auto-focus search input
- Sections: "תוצאות" (matches) → "פעולות מהירות"
- Fuzzy match against: category name, sub-category name, custom_tags, action verbs
- Keyboard nav: ↑↓ between rows, ↵ to execute, ESC to close
- Each row: icon · primary text · secondary text · keyboard shortcut hint

### 7.9 Activity Log panel
- Slides in from right (RTL = from left visually)
- Width: 360px desktop, full-screen sheet on mobile
- List of log entries with colored dot per action type:
  - green = create
  - blue = update
  - amber = reorder/pin
  - red = delete
- Each entry: dot · "{admin_name} {verb} {target_name}" · time-ago · undo/restore link
- Pagination: lazy-load older entries on scroll

### 7.10 Drag and Drop
- Use `flutter_reorderable_list` or `ReorderableListView`
- Drag handle = `⋮⋮` icon, only enabled in tree view
- During drag: card lifts with subtle shadow, others animate to make space
- On drop: write new `display_order` to Firestore, log to activity_log

### 7.11 Keyboard shortcuts (web)
| Key | Action |
|-----|--------|
| `↑↓` | navigate between rows |
| `Space` | select/deselect current row |
| `E` | open edit dialog for current row |
| `H` | toggle hide |
| `P` | toggle pin |
| `Del` | delete (with confirm) |
| `⌘K` / `Ctrl+K` | open command palette |
| `⌘Z` / `Ctrl+Z` | undo last action |
| `Esc` | close dialogs / clear selection |
| `/` | focus search input |

Implement via `RawKeyboardListener` wrapping the screen. On mobile, show only the on-screen elements.

---

## 8. State Management

Use the project's existing pattern (Provider/Riverpod — match what `admin_screen.dart` already uses).

### 8.1 `CategoriesV3Controller` exposes:
```dart
class CategoriesV3Controller extends ChangeNotifier {
  List<CategoryV3Model> categories;
  List<PromotedBanner> banners;
  Set<String> selectedIds;
  String searchQuery;
  CategoryFilter activeFilter;
  CategorySort activeSort;
  ViewMode viewMode;
  bool activityPanelOpen;
  bool commandPaletteOpen;

  // Streams
  Stream<List<CategoryV3Model>> watchCategories();
  Stream<List<ActivityLogEntry>> watchActivityLog({int limit = 50});

  // Actions
  Future<void> createCategory(CategoryV3Model c);
  Future<void> updateCategory(String id, Map<String, dynamic> patch);
  Future<void> deleteCategory(String id);
  Future<void> reorderCategory(String id, int newIndex);
  Future<void> bulkAction(BulkActionType action);
  Future<void> togglePin(String id);
  Future<void> toggleHide(String id);
  Future<void> undoLastAction();
  Future<void> executeCommand(CommandPaletteAction action);
}
```

### 8.2 Real-time updates
- `watchCategories()` returns a Firestore `snapshots()` stream — UI auto-updates
- Optimistic updates: write to local state immediately, rollback on Firestore error
- Show subtle "saving..." indicator in top bar while mutation is in flight

---

## 9. Accessibility & RTL Correctness

- All `EdgeInsets` → `EdgeInsetsDirectional`
- All `Alignment.centerLeft` → `AlignmentDirectional.centerStart`
- All icons that have direction (arrows, chevrons) → use `Directionality.of(context)` or built-in directional variants
- Semantic labels in Hebrew for screen readers
- Focus order matches visual order in RTL
- Test on both desktop web and mobile

---

## 10. Performance Requirements

- Initial render under 600ms with 50 categories cached
- Sparkline rendering uses `CustomPainter` with `shouldRepaint` returning false unless data changes
- Sub-category grids: lazy-render only when expanded
- Activity log: paginate, never load all entries at once
- Drag-and-drop reorder: debounce Firestore write by 500ms (in case user makes multiple drags)
- Search input: debounce by 200ms

---

## 11. Migration Strategy (Phased)

**Phase 1 (this prompt):** Build everything alongside the existing tab. Keep the old tab accessible via a feature flag `enable_categories_v3` in `remote_config`. Default to `false` initially.

**Phase 2 (after QA):** Flip flag to `true` for admin user `Avihai` only.

**Phase 3 (after 1 week stable):** Flip globally, archive old tab to `lib/admin/legacy/`.

**Backfill:**
- Run a one-time migration script (`scripts/backfill_category_analytics.dart`) that initializes `analytics` and `admin_meta` fields on all existing categories with default values
- Existing categories without analytics show "—" placeholders gracefully

---

## 12. Acceptance Criteria

The implementation is complete when ALL of the following pass:

- [ ] `flutter analyze` returns 0 issues on all new files
- [ ] All 11 existing categories from `home_screen.dart` render correctly with their actual icons/images
- [ ] Customer-facing home screen is visually unchanged (pixel-diff check)
- [ ] AnyTasks and נתינה מהלב banners appear in the promoted section and editing them updates the home screen
- [ ] Drag-and-drop reorder persists to Firestore and reflects in customer home within 5s
- [ ] Bulk actions work for: hide, pin, delete (with confirm), move to parent
- [ ] Command palette (⌘K) opens, searches fuzzy across all categories, and executes actions
- [ ] Activity log records every change with correct admin name + timestamp
- [ ] Undo restores the previous state for create/update/delete/reorder/pin/hide
- [ ] Sparkline displays correctly even with 0 data (flat line)
- [ ] Health score updates within 15 min of an order completion (via scheduled function)
- [ ] Search filters categories and sub-categories in real-time
- [ ] Saved views persist per admin user
- [ ] All 10 keyboard shortcuts work on web
- [ ] Mobile (Flutter on iOS/Android) renders without horizontal overflow at 360px width
- [ ] Hebrew RTL is correct everywhere (no LTR leak)
- [ ] Dark mode works across all components
- [ ] Loading states use skeleton screens, not spinners, for the main list

---

## 13. Implementation Order (recommended)

Execute in **phases**, confirming with Avihai before each phase:

### Phase A — Foundation (no UI changes visible yet)
1. Add new fields to Firestore schema (additive)
2. Write `updateCategoryAnalytics` Cloud Function + deploy
3. Run backfill script for existing categories
4. Build `CategoryV3Model`, `ActivityLogEntry`, `SavedView`, `PromotedBanner` models
5. Build `CategoriesV3Service`, `ActivityLogService`, `CategoryAnalyticsService`
6. Build `CategoriesV3Controller`

### Phase B — Core UI
7. `KpiMetricsRow` + `ToolbarBar` widgets
8. `CategoryRowCard` (without sparkline/funnel — basic version first)
9. `SubcategoryGrid` + `SubcategoryThumb`
10. `BannerRowCard` for AnyTasks + נתינה מהלב
11. Wire up everything in `admin_categories_v3_tab.dart`
12. Behind feature flag — enable only for Avihai

### Phase C — Advanced UI
13. `SparklineWidget` (custom painter)
14. `ConversionFunnelInline` + `CoverageChip` + `HealthScoreBar` + `CategoryStatusChips`
15. `BulkActionsBar` + selection logic
16. Drag-and-drop reorder
17. `KeyboardShortcutsHint` + actual key handlers

### Phase D — Power features
18. `ActivityLogPanel` + `logAdminAction` Cloud Function
19. `CommandPaletteOverlay` + fuzzy search + actions
20. `EditCategoryDialog` (5 tabs)
21. `AddCategoryDialog` (3-step wizard)
22. `PowerToolsFooter` (export JSON / import JSON / refresh images)
23. Saved views with `SavedViewsService`

### Phase E — Polish & QA
24. Loading skeletons
25. Empty states
26. Error toasts
27. Mobile responsive QA
28. Dark mode QA
29. Hebrew RTL QA
30. `flutter analyze` cleanup
31. Document new components in CLAUDE.md (new section §32)

---

## 14. Reference Files in Existing Codebase

**Match the patterns already in use:**
- For state management → look at `admin_ai_ceo_tab.dart` and `ai_ceo_service.dart`
- For Cloud Function structure → look at `updateVaultAnalytics` and `generateVaultAlerts` in `functions/index.js`
- For dialog patterns → look at the cleaning CSM block dialogs
- For chip styling → look at the existing badges in `admin_vault_tab.dart`
- For health-score-style indicators → look at the Vault Dashboard's three-layer commission display

**Hebrew strings:** All user-visible text in Hebrew, code comments in English. Match the tone of existing admin Hebrew strings (formal but friendly).

---

## 15. Definition of Done

When you finish, generate a CHANGES.md file listing:
- Every file created (with line count)
- Every file modified (with diff summary)
- Every Firestore collection touched
- Every Cloud Function added
- The exact `firebase deploy` commands needed
- A 5-step manual QA checklist for Avihai

Then run `flutter analyze` on all new files and report results.

---

**End of spec. Begin Phase A.**
