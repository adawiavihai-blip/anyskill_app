# Staging Environment Setup

## 1. Create the Firebase Staging Project

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Create a new Firebase project for staging
firebase projects:create anyskill-staging --display-name "AnySkill Staging"

# Add web app to staging project
firebase apps:create WEB --project anyskill-staging "AnySkill Staging Web"
```

## 2. Enable Services in Firebase Console

Go to https://console.firebase.google.com/project/anyskill-staging and enable:
- Authentication (Google + Phone)
- Cloud Firestore
- Cloud Storage
- Cloud Functions
- Hosting

## 3. Generate Service Account Keys

```bash
# Production key
firebase projects:get-service-account anyskill-6fdf3 > /tmp/prod-key.json

# Staging key
firebase projects:get-service-account anyskill-staging > /tmp/staging-key.json
```

Or from Firebase Console → Project Settings → Service Accounts → Generate New Private Key.

## 4. Add GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret Name | Value |
|-------------|-------|
| `FIREBASE_SERVICE_ACCOUNT_PROD` | Contents of prod service account JSON |
| `FIREBASE_SERVICE_ACCOUNT_STAGING` | Contents of staging service account JSON |
| `STRIPE_PUBLISHABLE_KEY` | `pk_live_51TF4Hm...` (your Stripe publishable key) |

## 5. Create the `staging` Branch

```bash
git checkout -b staging
git push -u origin staging
```

## 6. Deploy Rules & Functions to Staging

```bash
# Switch to staging project
firebase use anyskill-staging

# Deploy everything
firebase deploy --only firestore:rules,firestore:indexes,storage,functions

# Switch back to production
firebase use anyskill-6fdf3
```

## 7. Workflow

```
Feature branch → PR to master → CI runs analyze + test (no deploy)
                                  ↓ merge
                              master → CI builds + deploys to PRODUCTION

Feature branch → PR to staging → CI runs analyze + test (no deploy)
                                  ↓ merge
                              staging → CI builds + deploys to STAGING
```

## 8. Use Staging for Testing

Staging URL: `https://anyskill-staging.web.app`
Production URL: `https://anyskill-6fdf3.web.app`

Test on staging first. When confirmed working, merge staging → master for production deploy.
