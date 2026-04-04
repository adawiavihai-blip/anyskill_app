# AnySkill -- Deployment Keys & Signing Guide

> **This file contains instructions for generating production signing keys.**
> **NEVER commit actual passwords or keystore files to Git.**

---

## 1. Android Upload Keystore

### Generate the keystore (run ONCE on your machine):

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias anyskill-upload
```

You will be prompted for:
- **Keystore password** (choose a strong one, write it down)
- **Key password** (can be same as keystore password)
- **Name, Organization, etc.** (use your real business info)

### Place the keystore:

Move `upload-keystore.jks` to the `android/` directory:

```
anyskill_app/
  android/
    upload-keystore.jks   <-- here
    key.properties        <-- already created
```

### Fill in `android/key.properties`:

```properties
storePassword=YOUR_ACTUAL_STORE_PASSWORD
keyPassword=YOUR_ACTUAL_KEY_PASSWORD
keyAlias=anyskill-upload
storeFile=../upload-keystore.jks
```

### Test the release build:

```bash
flutter build appbundle --release
```

The signed `.aab` will be at `build/app/outputs/bundle/release/app-release.aab`.

---

## 2. iOS Signing (Apple Developer Program)

### Prerequisites:
- Apple Developer account ($99/year) at https://developer.apple.com
- Xcode installed on a Mac

### Bundle Identifier:
```
com.anyskill.app
```
This is already configured in:
- `ios/Runner.xcodeproj/project.pbxproj`
- `android/app/build.gradle.kts` (applicationId)

### Steps:
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** target → **Signing & Capabilities**
3. Set **Team** to your Apple Developer team
4. **Automatic signing** is recommended for development
5. For App Store submission, create a **Distribution certificate** + **Provisioning Profile** in Apple Developer portal

### Test the iOS build:

```bash
flutter build ipa --release
```

---

## 3. Firebase Configuration

Both platforms need Firebase config files:

| Platform | File | Location |
|----------|------|----------|
| Android | `google-services.json` | `android/app/google-services.json` |
| iOS | `GoogleService-Info.plist` | `ios/Runner/GoogleService-Info.plist` |
| Web | `firebase_options.dart` | `lib/firebase_options.dart` |

These are already in the project. If you change the Bundle ID / Application ID,
regenerate them from the Firebase Console.

---

## 4. Backup Strategy

### MUST backup (lose these = lose Play Store access):

| Item | Location | Backup To |
|------|----------|-----------|
| `upload-keystore.jks` | `android/` | Google Drive (encrypted) + USB drive |
| `key.properties` | `android/` | Same as above |
| Keystore password | In your head | Password manager (1Password/Bitwarden) |
| Apple Distribution cert | Keychain Access | Export as .p12, store with keystore |

### Recovery plan:
- **Lost Android keystore** = CANNOT update existing Play Store app. Must publish as new app.
- **Lost Apple cert** = Can regenerate from Apple Developer portal (revoke + recreate).

---

## 5. Sensitive Files Checklist

These files are in `.gitignore` and must NEVER be committed:

```
android/key.properties          # Keystore passwords
android/upload-keystore.jks     # The actual signing key
functions/.env                  # Stripe secret key
*.jks                           # Any Java keystore
*.keystore                      # Any Android keystore
```

---

## 6. Production Application IDs

| Platform | ID | Status |
|----------|-----|--------|
| Android | `com.anyskill.app` | Configured in build.gradle.kts |
| iOS | `com.anyskill.app` | Configured in project.pbxproj |
| Web | `anyskill-6fdf3.web.app` | Firebase Hosting |
| Firebase | `anyskill-6fdf3` | Project ID |

---

*Last updated: 2026-04-04 | Version: 9.1.5*
