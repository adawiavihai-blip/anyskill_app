# Quick Start — מה להדביק ל-Claude Code

> העתק את כל הטקסט שמתחת ל-`---` והדבק ל-Claude Code ב-VS Code.

---

# Task: AnySkill Categories Admin Tab v3 (Pro)

I want you to redesign the categories admin tab in AnySkill (Firebase project: anyskill-6fdf3) to a world-class management workspace matching the polish of Linear, Airbnb host dashboards, and Notion.

## Before you write any code

1. Read `CLAUDE.md` in the project root
2. Read `lib/admin/admin_screen.dart` to understand the current tab structure
3. Read the existing `admin_categories_tab.dart` (or whatever the current file is called) to understand what we're replacing
4. Read `lib/admin/admin_vault_tab.dart` to match the chip / card / styling patterns
5. Read `lib/admin/admin_ai_ceo_tab.dart` to match the state management pattern
6. Read `functions/index.js` to see how `updateVaultAnalytics` is structured (we'll mirror that pattern)

## Critical constraints

- **DO NOT change the customer-facing home screen.** Categories must render identically for users.
- **DO NOT remove any existing Firestore fields.** All schema changes are additive.
- **DO NOT change CSM blocks** (cleaning/massage/delivery/handyman/pest_control).
- **Keep the old tab functional** behind a Remote Config flag `enable_categories_v3` (default `false`).
- **Hebrew RTL throughout.** Use `EdgeInsetsDirectional` and `AlignmentDirectional` everywhere.
- **Match the existing project's state management** (Provider/Riverpod — whichever is already in use).

## Phased execution — STOP AND CONFIRM after each phase

I want you to work in 5 phases. After each phase, stop, summarize what you did, and wait for me to type "Phase X approved, continue" before moving on.

### Phase A — Foundation (no UI change visible)
- Add new Firestore fields (analytics, admin_meta, csm_module, custom_tags) to `categories` collection — additive only
- Create new collections: `admin_activity_log`, `admin_saved_views`, `promoted_banners`
- Add composite indexes to `firestore.indexes.json`
- Build and deploy `updateCategoryAnalytics` Cloud Function (scheduled every 15 min, uses Gemini 2.5 Flash Lite if any AI work is needed)
- Build and deploy `logAdminAction` and `undoAdminAction` callable Cloud Functions
- Create models: `CategoryV3Model`, `ActivityLogEntry`, `SavedView`, `PromotedBanner`, `CommandPaletteAction`
- Create services: `CategoriesV3Service`, `ActivityLogService`, `CategoryAnalyticsService`, `CommandPaletteService`, `SavedViewsService`
- Create controllers: `CategoriesV3Controller`, `SelectionController`
- Run a backfill script for existing categories with default analytics values
- Run `flutter analyze` — must return 0 issues

### Phase B — Core UI (basic version, behind feature flag)
- Build `KpiMetricsRow` (5 KPI cards)
- Build `ToolbarBar` (search + filter + sort + view switcher)
- Build `CategoryRowCard` — basic version (no sparkline/funnel yet, just name/chips/health)
- Build `SubcategoryGrid` + `SubcategoryThumb`
- Build `BannerRowCard` for AnyTasks + נתינה מהלב (these become managed entities in `promoted_banners`)
- Build `EmptyStateWidget`
- Wire up `admin_categories_v3_tab.dart` and route it behind the Remote Config flag
- Whitelist my admin uid so only I see it
- Run `flutter analyze`

### Phase C — Advanced UI
- Build `SparklineWidget` (custom painter, 60×28px, green/red based on growth)
- Build `ConversionFunnelInline` (views → clicks → orders display)
- Build `CoverageChip` (🌍 X cities)
- Build `HealthScoreBar` (50px wide, color by threshold)
- Build `CategoryStatusChips` (active/popular/hot/CSM/warning)
- Build `BulkActionsBar` (sticky, appears when selections > 0)
- Implement drag-and-drop reorder (use `ReorderableListView` or `flutter_reorderable_list`)
- Implement keyboard shortcuts (↑↓ Space E H P ⌘K ⌘Z Esc /)
- Build `KeyboardShortcutsHint` (dismissable strip)
- Run `flutter analyze`

### Phase D — Power features
- Build `ActivityLogPanel` (slide-in from RTL-start side, 360px desktop, full-screen on mobile)
- Build `CommandPaletteOverlay` (⌘K modal with fuzzy search + actions)
- Build `EditCategoryDialog` (5 tabs: details / image / sub-categories / providers / stats)
- Build `AddCategoryDialog` (3-step wizard: details → image → sub-categories)
- Build `ConfirmDestructiveDialog` (type-to-delete pattern)
- Build `SavedViewDialog`
- Build `PowerToolsFooter` (refresh images, reset popularity, export JSON, import JSON)
- Wire up undo via `undoAdminAction` Cloud Function
- Run `flutter analyze`

### Phase E — Polish & QA
- Add loading skeletons for the main list
- Add proper empty states for each section
- Add error toasts with retry actions
- Verify mobile responsive (360px width minimum)
- Verify dark mode across all components
- Verify Hebrew RTL is correct everywhere — no LTR leaks
- Optimize: debounce search (200ms), debounce reorder writes (500ms)
- Update `CLAUDE.md` with a new section §32 documenting the v3 categories architecture
- Generate `CHANGES.md` listing every file created/modified, every Firestore collection touched, every Cloud Function added, exact `firebase deploy` commands, and a 5-step manual QA checklist for me
- Final `flutter analyze` — must return 0 issues

## Acceptance criteria

The implementation is complete when ALL of these pass:
- `flutter analyze` returns 0 issues
- All 11 existing categories from the home screen render correctly with their actual icons
- Customer-facing home screen is visually unchanged (pixel-diff check)
- Drag-and-drop reorder persists to Firestore and reflects in customer home within 5s
- Bulk actions work: hide, pin, delete (with confirm), move to parent
- Command palette (⌘K) opens, fuzzy-searches, executes actions
- Activity log records every change with admin name + timestamp
- Undo restores previous state for create/update/delete/reorder/pin/hide
- Sparkline displays correctly even with 0 data (flat line)
- Health score updates within 15 min of an order completion
- All 10 keyboard shortcuts work on web
- Mobile renders without horizontal overflow at 360px width
- Hebrew RTL is correct throughout
- Dark mode works
- Loading states use skeletons, not spinners

## Begin Phase A now. Stop after Phase A and wait for my approval.
