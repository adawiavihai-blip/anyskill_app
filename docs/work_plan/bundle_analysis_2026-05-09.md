# 📦 Bundle Analysis — 2026-05-09

**Source build**: `flutter build web --release` (current `build/web/`)
**Total uncompressed**: 37 MB
**Total gzipped (estimated initial download)**: ~7 MB

---

## TL;DR

The app's first paint requires **~3 MB gzipped of JavaScript/WASM** + a deferred
`canvaskit.wasm` of **2.7 MB gzipped**. Total time-to-interactive on a typical
4G connection: ~4-6 seconds. Acceptable for a Flutter Web PWA, but there are
clear optimization wins below.

## Top-level breakdown (uncompressed → gzipped)

| Asset | Uncompressed | Gzipped (est.) | What it is |
|-------|--------------|----------------|------------|
| **canvaskit/** | 24 MB | ~5 MB | Skia/CanvasKit WASM renderer (Flutter's WebGL backend) |
| **main.dart.js** | 9.3 MB | **2.5 MB** | Compiled Dart code — your entire app logic |
| **assets/** | 3.1 MB | ~1.5 MB | Images, fonts, audio, icons |
| **icons/** | 244 KB | ~120 KB | PWA icons (multiple resolutions) |
| **index.html** | 12 KB | 4 KB | Entry point |
| **flutter_service_worker.js** | 12 KB | 4 KB | PWA service worker |
| **app_init.js** | 12 KB | 4 KB | Watchdog + cache-bust logic (CLAUDE.md §9b Law 15) |

## CanvasKit deep-dive (24 MB uncompressed)

The biggest single contributor. Breakdown:

| File | Uncompressed | Gzipped | Notes |
|------|--------------|---------|-------|
| `canvaskit.wasm` | 6.7 MB | **2.7 MB** | Main WebGL renderer for Chromium |
| `chromium/` | 6.6 MB | ~2.7 MB | Chromium-specific renderer (sub-folder) |
| `skwasm_st.wasm` | 3.3 MB | 1.4 MB | Single-threaded fallback |
| `skwasm.wasm` | 3.3 MB | 1.4 MB | Multi-threaded variant |
| `skwasm_st.js.symbols` | 1.4 MB | dev-only | Debug symbols (NOT shipped to users) |
| `skwasm.js.symbols` | 1.4 MB | dev-only | Debug symbols |
| `canvaskit.js.symbols` | 1.3 MB | dev-only | Debug symbols |
| `canvaskit.js` | 85 KB | 26 KB | Loader |
| `skwasm.js` | 65 KB | 20 KB | Loader |
| `skwasm_st.js` | 57 KB | 18 KB | Loader |

**~4 MB of `*.js.symbols` files in `canvaskit/` are debug-only** and should
be excluded from the deployed bundle. Firebase Hosting still serves them
because they're in the Flutter SDK output. **Action**: configure Firebase
Hosting to skip `*.symbols` files in `firebase.json` `hosting.ignore`.

Estimated savings: ~4 MB raw (~1 MB gzipped) instant.

## main.dart.js (9.3 MB uncompressed → 2.5 MB gzipped)

This is your entire compiled Dart code. The contributors (estimated based
on imports in `pubspec.yaml`):

| Likely contributor | Estimated share | Notes |
|--------------------|-----------------|-------|
| Firebase SDKs (cloud_firestore, auth, storage, etc.) | ~30% | 11+ Firebase packages bundled |
| Flutter framework + Material widgets | ~20% | unavoidable baseline |
| Maps stack (flutter_map + latlong2 + proj4dart) | ~10% | could be lazy-loaded if rare-use |
| flutter_riverpod + generated providers | ~5% | |
| Stripe / payment (legacy code per CLAUDE.md §2) | ~3% | could be removed if Stripe is dead |
| video_player / image_picker / cached_network_image | ~5% | |
| Anthropic SDK + Gemini integration glue | ~3% | could be lazy-loaded for non-admin |
| Sentry + Crashlytics + Performance | ~3% | |
| 8 CSMs (massage/pest/delivery/...) | ~5% | each is a self-contained block |
| AnyTasks + Pet Stay + Flash Auction | ~3% | |
| Shared services + utilities | ~13% | i18n, locale, theme, etc. |

**Note**: these are educated estimates. To get exact numbers, run:

```bash
flutter build web --release --analyze-size --target-platform=web-javascript
```

This generates a Chrome DevTools-format report in `build/devtools/`. Open it
with `flutter pub global run devtools` for an interactive treemap.

## assets/ breakdown (3.1 MB uncompressed)

| File | Size | Notes |
|------|------|-------|
| `assets/images/NEW_LOGO1.png.png` | **604 KB** ⚠️ | Single PNG. **Optimize this!** |
| `assets/audio/` (sound studio) | 288 KB | 4 sound files |
| `assets/fonts/NotoSansHebrew-Regular.ttf` | 46 KB | Hebrew RTL fallback |
| `assets/fonts/NotoSansHebrew-Bold.ttf` | 46 KB | Hebrew RTL fallback |
| `MaterialIcons-Regular.otf` | 95 KB | Standard Material Icons |

**Action item**: `NEW_LOGO1.png.png` is 604 KB and named oddly (double `.png`).
Convert to WebP and resize:

```bash
# 604KB PNG → ~80KB WebP at the same visual quality
cwebp -q 85 assets/images/NEW_LOGO1.png.png -o assets/images/logo.webp
```

Estimated savings: ~520 KB raw.

## What gets downloaded on first visit (gzipped)

A fresh user's browser loads, in order:
1. `index.html` (4 KB)
2. `flutter.js` + `flutter_bootstrap.js` (~50 KB)
3. `main.dart.js` (**2.5 MB gzipped**) — blocks first paint
4. `canvaskit.wasm` (**2.7 MB gzipped**) — blocks first paint
5. Fonts (~50 KB gzipped)
6. Logo + icons (~600 KB if PNG, ~80 KB if WebP)

**Total critical path**: ~5.5-6 MB gzipped → 4-7s on 4G, 1-2s on cable.

## Recommended optimizations (priority order)

### 🥇 Quick wins (1-2 hours each, no risk)

1. **Exclude `.symbols` files from deploy** — saves 4 MB raw / 1 MB gzipped.
   Add to `firebase.json`:
   ```json
   "hosting": {
     "ignore": ["**/*.symbols", "..."]
   }
   ```

2. **Convert NEW_LOGO1.png.png to WebP + resize** — saves ~520 KB.
   Also rename (the double `.png` extension is a sign of a sloppy export).

3. **Use Brotli on Firebase Hosting** — Firebase Hosting auto-uses Brotli
   when the client supports it (most browsers do). Verify: `curl -H "Accept-Encoding: br" -I https://anyskill-6fdf3.web.app/main.dart.js`
   If `Content-Encoding: br` appears, you're already saving ~25% over gzip.

### 🥈 Medium effort (4-8 hours)

4. **Tree-shake unused Firebase packages** — review `pubspec.yaml` for
   Firebase deps that the app no longer uses. CLAUDE.md §2 mentions Stripe
   was removed in v11.9 — confirm `stripe` related packages are also gone.

5. **Lazy-load maps stack** — `flutter_map + latlong2 + proj4dart` is
   ~1 MB raw and only used in: subcategory map view, address pickers,
   GPS tracking. If `Navigator.push` to maps screens is uncommon
   (most users just browse), lazy-load via deferred imports.

6. **Lazy-load admin panel** — the entire admin codebase (Vault, Banners
   Studio, Sound Studio, Monetization, etc.) is bundled into main.dart.js
   for ALL users, even though only ~3 admins ever see it. Move admin code
   behind a deferred import.

### 🥉 Large effort (>1 day, big payoff)

7. **Switch to HTML renderer** for the marketplace pages, keep CanvasKit
   for editing/admin — this is a config flag in Flutter, but requires
   testing because some widgets render differently. Could save ~5 MB
   of canvaskit downloads for browse-only sessions.

8. **Code-splitting via deferred imports** — Dart supports `deferred as`
   imports that delay download until first call. Can reduce `main.dart.js`
   initial download by 30-50%.

## Tracking

The CI build job (`.github/workflows/ci.yml`) now reports the bundle size
in every PR's GitHub Summary. Track over time:

| Date | main.dart.js | total | Notes |
|------|--------------|-------|-------|
| 2026-05-09 | 9.3 MB | 37 MB | baseline (this report) |
| (future runs) | … | … | |

**Threshold**: warning at `main.dart.js > 15 MB` (already configured in
`.github/workflows/ci.yml`). Plan to harden to error-level once we
implement the quick wins above.

## Tools used

- `du -sh` for file sizes
- `gzip -k -c | wc -c` for gzipped estimate
- Build command: `flutter build web --release`

## Action items checklist

- [x] **Exclude `*.symbols` + `*.map` from `firebase.json` hosting deploy** —
      done 2026-05-10. Saves ~4 MB raw on each deploy.
- [x] **Verify Brotli is active on production** — verified 2026-05-10.
      Production main.dart.js: **1.85 MB** (Brotli) vs 2.53 MB (gzip)
      vs 9.69 MB (uncompressed). Brotli is 27% smaller than gzip, and
      80.9% smaller than uncompressed. No action needed; already optimal.
- [x] **Audit `pubspec.yaml` for stale Stripe-related deps** — done
      2026-05-10. **Zero Stripe deps remain.** `webview_flutter` is a
      transitive dep of `youtube_player_iframe` (Academy player), not
      stale. No removable code.
- [ ] Convert `NEW_LOGO1.png.png` → WebP + rename — **DEFERRED**.
      Requires `cwebp` binary (not installed locally) + 14+ reference
      updates across `lib/` + `pubspec.yaml`. Better as a focused PR
      with manual review.
- [ ] Plan deferred imports for maps and admin code (1-day work each)

## Production verification (2026-05-10)

| Asset | Compression | Size | Saved |
|-------|-------------|------|-------|
| `main.dart.js` | none | 9.69 MB | (baseline) |
| `main.dart.js` | gzip | 2.53 MB | 73.8% |
| `main.dart.js` | **brotli** | **1.85 MB** | **80.9%** |

Tested via `curl -H "Accept-Encoding: br" -I https://anyskill-6fdf3.web.app/main.dart.js`.
The `Content-Encoding: br` header confirms Firebase Hosting serves Brotli
to compatible clients (all modern browsers). No further work needed.

---

*Generated 2026-05-09 by automated bundle analysis. Re-run after major
dependency changes.*
