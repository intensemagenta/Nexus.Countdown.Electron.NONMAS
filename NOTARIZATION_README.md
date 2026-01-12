# Notarization Guide for Developer ID Distribution

This guide explains how to build a signed macOS app ready for Apple notarization, for distribution outside the Mac App Store.

## Prerequisites

- **Developer ID Application certificate** installed in your Keychain
  - Certificate name: `Developer ID Application: Adam Parsons (T6YG6KXA9D)`
  - If you have the `.cer` file, double-click it to install it in Keychain Access

- **Apple Developer Account** with access to notarization services

## Quick Start

### 1. Build the Signed App

Run the build script from the repository root:

```bash
npm run build:for-notarization
```

This will:
- Build the app bundle with electron-builder
- Sign the app bundle with your Developer ID certificate
- Enable hardened runtime (required for notarization)
- Sign all nested executables (helper apps, frameworks)
- Create a signed DMG
- Create a zip file ready for Apple portal upload

### 2. Verify the Build

Verify that everything is ready for notarization:

```bash
npm run verify:notarization-ready
```

This checks:
- App bundle signature validity
- Hardened runtime is enabled
- All nested executables are signed
- DMG signature is valid
- Zip file is ready

### 3. Test Locally (Optional but Recommended)

Before uploading to Apple, test the DMG locally:

```bash
open apps/electron/dist/non_mas/Nexus\ Countdown*.dmg
```

Install and run the app to ensure it works correctly. Note that Gatekeeper may show a warning before notarization - this is expected.

### 4. Upload to Apple's Notarization Portal

1. **Go to Apple Developer Portal:**
   - Visit: https://developer.apple.com/account/resources/certificates/list
   - Sign in with your Apple Developer account

2. **Navigate to Notarization:**
   - Go to: https://developer.apple.com/account/resources/certificates/list
   - Or use the direct notarization upload page

3. **Upload the Zip File:**
   - Upload: `apps/electron/dist/non_mas/Nexus Countdown-for-notarization.zip`
   - This contains the signed app bundle
   - Apple will process the notarization (typically takes 5-15 minutes)

4. **Check Status:**
   - Monitor the notarization status in the portal
   - You'll receive an email when it's complete

### 5. After Notarization is Approved

Once Apple approves the notarization:

1. **Staple the Ticket:**
   ```bash
   cd apps/electron/dist/non_mas
   
   # Staple to app bundle
   xcrun stapler staple "Nexus Countdown.app"
   
   # Staple to DMG
   xcrun stapler staple "Nexus Countdown"*.dmg
   ```

2. **Verify Stapling:**
   ```bash
   xcrun stapler validate "Nexus Countdown.app"
   xcrun stapler validate "Nexus Countdown"*.dmg
   ```

3. **Test Again:**
   - The DMG should now pass Gatekeeper without warnings
   - Users can install and run without security prompts

## Build Outputs

All files are created in `apps/electron/dist/non_mas/`:

- **`Nexus Countdown.app`** - Signed app bundle (in `mac/`, `mac-arm64/`, or `mac-x64/` subdirectory)
- **`Nexus Countdown-*.dmg`** - Signed DMG installer (ready for testing and distribution)
- **`Nexus Countdown-for-notarization.zip`** - Zip file for Apple portal upload

## Troubleshooting

### Certificate Not Found

If you see "Developer ID certificate not found":

1. Check that the certificate is installed:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID"
   ```

2. If not found, install the certificate:
   - Double-click `cert/developerID_application.cer`
   - Or import via Keychain Access: File → Import Items

### Signature Verification Fails

If signature verification fails:

1. Check that hardened runtime is enabled:
   ```bash
   codesign -d --entitlements - "apps/electron/dist/non_mas/mac/Nexus Countdown.app"
   ```

2. Verify all nested executables are signed:
   ```bash
   codesign -vvv --deep --strict "apps/electron/dist/non_mas/mac/Nexus Countdown.app"
   ```

### Gatekeeper Rejects Before Notarization

This is **normal** before notarization. After notarization and stapling, Gatekeeper will accept the app.

### Notarization Fails

If Apple rejects the notarization:

1. Check the notarization log in Apple Developer portal
2. Common issues:
   - Missing hardened runtime
   - Unsigned nested executables
   - Invalid entitlements
   - Missing or incorrect code signing

3. Fix the issues and rebuild:
   ```bash
   npm run build:for-notarization
   ```

## Manual Notarization (Alternative)

If you prefer to use command-line tools instead of the portal:

### Using xcrun notarytool (macOS 13+)

```bash
# Submit for notarization
xcrun notarytool submit \
  --apple-id "your-apple-id@example.com" \
  --password "app-specific-password" \
  --team-id "T6YG6KXA9D" \
  "apps/electron/dist/non_mas/Nexus Countdown-for-notarization.zip"

# Check status
xcrun notarytool history \
  --apple-id "your-apple-id@example.com" \
  --password "app-specific-password" \
  --team-id "T6YG6KXA9D"
```

### Using altool (Legacy, macOS 12 and earlier)

```bash
xcrun altool --notarize-app \
  --primary-bundle-id "com.nexuscountdown" \
  --username "your-apple-id@example.com" \
  --password "app-specific-password" \
  --file "apps/electron/dist/non_mas/Nexus Countdown-for-notarization.zip"

# Check status
xcrun altool --notarization-info <UUID> \
  --username "your-apple-id@example.com" \
  --password "app-specific-password"
```

## Notes

- **Hardened Runtime** is REQUIRED for notarization
- All nested executables (helper apps, frameworks) must be signed
- App bundle must be zipped for Apple portal upload (DMG can be uploaded directly)
- Notarization typically takes 5-15 minutes
- Stapling must happen after successful notarization
- The DMG can be tested locally before notarization, but Gatekeeper will show warnings

## Related Files

- Build script: `scripts/build-for-notarization.sh`
- Verification script: `scripts/verify-notarization-ready.sh`
- Entitlements: `apps/electron/build/entitlements.dev-id.plist`
- Inherit entitlements: `apps/electron/build/entitlements.dev-id.inherit.plist`

