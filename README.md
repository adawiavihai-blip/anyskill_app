# AnySkill

[![CI](https://github.com/avihai-anyskill/anyskill_app/actions/workflows/ci.yml/badge.svg)](https://github.com/avihai-anyskill/anyskill_app/actions/workflows/ci.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.7%2B-02569B?logo=flutter)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Hosting%20%2B%20Firestore-FFCA28?logo=firebase)](https://firebase.google.com/)
[![Tests](https://img.shields.io/badge/tests-919%20passing-brightgreen)]()
[![License](https://img.shields.io/badge/license-Proprietary-red)]()

RTL-first (Hebrew + Arabic) service marketplace connecting customers with
verified service providers. Flutter + Firebase, deployed as a PWA at
[anyskill-6fdf3.web.app](https://anyskill-6fdf3.web.app).

---

## Quick start

```bash
flutter pub get
flutter run -d chrome
```

For setup details, see [CLAUDE.md](./CLAUDE.md) — the canonical project guide.

---

## Documentation

| Doc | Purpose |
|-----|---------|
| [CLAUDE.md](./CLAUDE.md) | Architecture, business rules, payment flows, ALL conventions (single source of truth) |
| [TESTING.md](./TESTING.md) | How to run + write tests across all 4 suites |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Deploy runbook + manual operator steps |
| `docs/work_plan/` | Sessional progress reports |

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Client | Flutter 3.7+, Dart, Riverpod |
| Auth | Firebase Auth (Google, Apple, Phone/OTP) |
| Database | Cloud Firestore (43+ collections) |
| Storage | Firebase Storage |
| Functions | Cloud Functions for Firebase (Node.js 24, 50+ CFs) |
| AI | Anthropic Claude (Opus + Haiku) + Gemini 2.5 Flash Lite |
| Maps | flutter_map + OpenStreetMap |
| i18n | 4 locales: he / en / es / ar |
| Monitoring | Sentry + Firebase Crashlytics + Watchtower |
| Hosting | Firebase Hosting (SPA) |

---

## Test coverage

| Suite | Count | Runtime |
|-------|-------|---------|
| Flutter unit/widget | 524+ | ~5s |
| Cloud Functions | 258 | ~2s |
| Firestore Rules | 137 | ~7s (with emulator) |
| E2E (web smoke) | 1 | ~30s |
| **Total in CI** | **920+** | ~45s |

All gated in CI — every PR must pass before merge.

---

## Quality gates

- `flutter analyze` → 0 issues required
- Lighthouse CI gates (perf / a11y / SEO / best-practices)
- Firestore Rules tests cover every security-sensitive collection
- CF tests cover every callable, trigger, and scheduled function
