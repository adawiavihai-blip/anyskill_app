# Deployment Runbook — AnySkill

Canonical deploy checklist. Distilled from across CLAUDE.md sections.
Always run from the project root: `c:\Users\aviha\Desktop\anyskill_app`.

---

## Pre-deploy checklist

Before EVERY deploy, run:

```bash
# 1. Analyzer must be 0 issues
flutter analyze
# → "No issues found!"

# 2. Flutter tests
flutter test test/unit/
# → "All tests passed!" (524+)

# 3. Cloud Functions tests
cd functions && npx jest __tests__/auth.test.js && cd ..
# → "Tests: 258 passed, 258 total"

# 4. (Optional but recommended) Rules tests
export JAVA_HOME="$PWD/tools/jre21/jdk-21.0.11+10-jre"
export PATH="$JAVA_HOME/bin:$PATH"
firebase emulators:exec --only firestore,storage --project=anyskill-rules-tests \
  "cd firestore-rules-tests && npm test"
# → "137 passed"

# 5. (Optional) Build size check
flutter build web --release
ls -lh build/web/main.dart.js
# → ~7.74 MB raw / 2.07 MB gzip / ~1.50 MB brotli
```

If any of these fail, FIX BEFORE DEPLOYING. Production users always.

---

## Deploy paths by change type

### Pure client (Flutter only)

```bash
flutter build web --release
firebase deploy --only hosting
```

Time: ~3-5 min. Risk: low. Rollback: `firebase hosting:rollback`.

### New Firestore rule

```bash
firebase deploy --only firestore:rules
```

Time: ~30 sec. Risk: HIGH if rule is wrong (could lock users out or
leak data). **Always run rules tests first.**

### New composite index

```bash
firebase deploy --only firestore:indexes
```

Time: 30 sec for queue, 1-5 minutes for index to build.
**While indexes build, queries that need them return EMPTY results
silently** — schedule deploys at low-traffic windows.

### New Storage rule

```bash
firebase deploy --only storage
```

⚠️ Note: NOT `storage:rules` — Storage has no sub-targets. The
`firebase.json` `storage.rules` config maps to `storage.rules`.

### New Cloud Function

```bash
# Single function:
firebase deploy --only functions:myNewFunction

# Multiple:
firebase deploy --only functions:funcA,functions:funcB,functions:funcC
```

Time: 2-5 min per function. Risk: medium. CFs auto-create their
Cloud Scheduler jobs on first deploy (`onSchedule` only).

### Existing CF + secrets (Anthropic / Gemini)

If the CF needs a new secret, set it FIRST:

```bash
firebase functions:secrets:set GEMINI_API_KEY
# (paste key when prompted)

# Then deploy:
firebase deploy --only functions:myFunction
```

The secret is bound to the CF via the `secrets: [GEMINI_API_KEY]`
option in the CF definition.

---

## Post-deploy verification

```bash
# 1. Hosting smoke check
curl -sI https://anyskill-6fdf3.web.app | head -5

# 2. Function trigger check (for newly-deployed schedulers)
firebase functions:log --only myNewFunction --lines 5

# 3. Live error monitoring
# - Sentry: https://sentry.io/organizations/anyskill/
# - Firebase Console → Crashlytics
# - Admin → Performance Observatory tab (in-app)
```

---

## Manual operator steps (one-time, not automated)

These cannot be deployed via CLI. Document in writing when you do them.

### TTL policies (CLAUDE.md §19, §38)

Required for two scheduled CFs that write `expireAt` timestamps but
need TTL to actually delete the docs:

1. https://console.cloud.google.com/firestore/databases/-default-/ttl
2. Click "Create Policy"
3. Collection group: `error_logs`, field: `expireAt`
4. Repeat for: `activity_log`

Without these, both collections grow forever. Correctness is unaffected
(TTL deletes consume no quota). One-time setup; survives forever.

Future TTL collections (post-launch):
- `sound_events_log` (expireAt 30d)
- `sound_system_log` (expireAt 90d)
- `ai_provider_order` (expireAt 1h cache)

### App Check Enforce mode (CLAUDE.md §50)

Currently in **Monitor mode** (warns but doesn't block). To flip to
Enforce:

1. https://console.firebase.google.com/project/anyskill-6fdf3/appcheck
2. Per-API: flip from "Monitor" to "Enforce"
3. Wait 24-48h with Monitor logs clean before enforcing

This blocks any non-app client from hitting Firestore/Functions.

### FCM tokens populated (CLAUDE.md §57)

Several CFs (notifyOnFlashAuctionOffer, vault alerts, broadcast)
silently no-op when target users have no `fcmToken`. Verify token
registration after first deploy:

```bash
firebase firestore:databases:exec \
  "SELECT COUNT(*) FROM users WHERE fcmToken != null"
```

### Email Trigger Extension

Several CFs write to the `mail` collection expecting the Firebase
Trigger Email Extension to deliver. Verify it's installed + active:

1. https://console.firebase.google.com/project/anyskill-6fdf3/extensions
2. Look for "Trigger Email" — should be "Active"

If NOT active, the following CFs silently fail to send mail:
- `reengageAbandonedLeads`
- `sendEmailVerificationCode`
- payment receipts
- review reminders

---

## Rollback procedures

### Hosting rollback

```bash
firebase hosting:channel:list
firebase hosting:rollback
# Or via console: Hosting → Release history → "Rollback"
```

Reverts to previous release. Takes ~10 sec.

### Cloud Function rollback

There's no native rollback. Two options:

1. `git revert` the CF code, then `firebase deploy --only functions:X`
2. Roll forward: edit the CF to early-return, then deploy.

For CRITICAL functions (money flows), prefer the early-return
roll-forward — leaves an audit trail in git.

### Rules rollback

```bash
git checkout <previous-commit> -- firestore.rules
firebase deploy --only firestore:rules
```

⚠️ A bad rule can lock all users out. Test in the emulator FIRST
before pushing to prod.

### Index rollback

Indexes are rarely rolled back — usually you add or update. To remove
a now-unused index, edit `firestore.indexes.json` and redeploy.

---

## Emergency procedures

### Money flow regression discovered in production

1. **Stop the bleeding**: edit the CF (in firebase functions shell or
   git) to early-return on the broken path
2. Deploy the fix immediately
3. Audit `transactions` + `platform_earnings` for the affected period
4. Issue refunds via `grantAdminCredit` CF if needed
5. Post-mortem: write a CLAUDE.md section + add a regression test

### Security regression (admin gate broken)

1. Check `admin_audit_log` for unauthorized actions during the window
2. If breach confirmed: revoke affected admins via:
   ```bash
   node -e "
     const admin = require('firebase-admin');
     admin.initializeApp();
     admin.auth().setCustomUserClaims(UID, { admin: false })
       .then(() => admin.auth().revokeRefreshTokens(UID));
   "
   ```
3. Roll back the broken rule/CF
4. Run `backfillAdminClaims` to verify all claims match Firestore state

### Data loss prevention

There's no automated backup. To enable:

1. Enable Firestore PITR: https://firebase.google.com/docs/firestore/use-pitr
2. Setup `scheduledFirestoreBackup` CF (already exists, runs daily)

---

## Which environment am I deploying to?

Single environment: `anyskill-6fdf3` (production).

There is NO staging. Test changes locally with the emulator. Major
features should be gated behind a feature flag (e.g., the v3 categories
whitelist in §45) and rolled out to specific UIDs first.

---

## Daily ops surfaces

| Thing to check | Where |
|----------------|-------|
| User-facing errors | Sentry |
| Native crashes | Firebase Crashlytics |
| Custom error logs | Admin → Performance Observatory tab |
| Activity feed | Admin → Live Feed tab |
| Money totals | Admin → Vault dashboard (CLAUDE.md §29) |
| AI usage cost | Admin → Monetization → Cost panel |
| Stuck escrow jobs | Admin → Vault → Alerts |
| Stale support tickets | Admin → Support Inbox |
| CF execution logs | `firebase functions:log` |

---

*Last updated: 2026-05-10 (consolidated from CLAUDE.md sections after
BONUS 18 sweep).*
