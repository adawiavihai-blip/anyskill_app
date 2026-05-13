# 📋 Work Plan — 2026-05-10 (Session 3)

**Goal**: extend test coverage on money paths + finish accessibility on the
booking flow. All autonomous, low-risk work.

**Status legend**: 🟡 in progress · ✅ done · ⏸ deferred

---

## Priority order

### 🔥 HIGH — Money-path test coverage

#### 1. ✅ Happy-path tests for `grantAdminCredit`
- **Why**: 11 rejection tests already exist, but ZERO happy-path coverage.
  If a future change breaks the success flow → no test catches it.
- **Target tests**:
  - Valid admin grants 100₪ to target user → tx commits, balance increments
  - Idempotency replay returns cached result without touching balance
  - Daily cap check inside tx (verified via mock query)
- **Output**: 2-3 new tests in `functions/__tests__/auth.test.js`

### 🟢 MEDIUM — More accessibility coverage

#### 2. ✅ Semantics on booking sheet inputs (date picker, time slots)
- **Why**: a booking failure on the date picker leaves screen-reader
  users completely stuck (no error message + no way out).
- **Target widgets**: in `expert_profile_screen.dart`, the date picker
  buttons + time-slot chips inside the booking sheet.
- **Output**: 2-3 Semantics wrappers

### 🟡 LOWER

#### 3. ⏸ Lazy-load admin panel
- **Defer reason**: 4-8 hours of careful refactoring. Best as a focused
  PR with full build-time validation, not autonomous work.

#### 4. ⏸ Happy-path test for `processPaymentRelease`
- **Defer reason**: more complex transaction (escrow + commission split
  + dual writes). Push to next session.

---

## Files I'll touch

- `functions/__tests__/auth.test.js` (item 1)
- `lib/screens/expert_profile_screen.dart` (item 2)
- `docs/work_plan/PROGRESS_2026-05-10_session3.md` (final report)

---

## Progress log

| Time | Item | Status |
|------|------|--------|
| start | Plan created | ✅ |
| | Item 1 | ✅ 3 happy-path tests added — all passing |
| | Item 2 | ✅ 2 Semantics widgets on booking sheet |
| | Items 3-4 | ⏸ deferred |
