# Complete Guide: Building and Notarizing macOS Apps for Distribution Outside the Mac App Store

This guide provides a complete, step-by-step recipe for building, signing, and notarizing macOS applications for distribution outside the Mac App Store. This is essential for apps distributed via direct download, websites, or third-party platforms.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Build Configuration](#build-configuration)
4. [Building the Signed App](#building-the-signed-app)
5. [Manual Signing Process](#manual-signing-process)
6. [Creating the DMG](#creating-the-dmg)
7. [Submitting for Notarization](#submitting-for-notarization)
8. [Stapling the Notarization Ticket](#stapling-the-notarization-ticket)
9. [Verification and Testing](#verification-and-testing)
10. [Troubleshooting](#troubleshooting)
11. [Automation Scripts](#automation-scripts)

---

## Prerequisites

### 1. Apple Developer Account

- Active Apple Developer Program membership ($99/year)
- Access to notarization services (included with membership)
- Your **Team ID** (found at https://developer.apple.com/account)

### 2. Developer ID Certificate

You need a **Developer ID Application** certificate:

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click the **+** button to create a new certificate
3. Select **Developer ID Application** under "Services"
4. Follow the instructions to create a Certificate Signing Request (CSR)
5. Download and install the certificate in your Keychain

**Certificate Name Format:**
```
Developer ID Application: Your Name (TEAM_ID)
```

### 3. App-Specific Password

For command-line notarization, create an app-specific password:

1. Go to https://appleid.apple.com/account/manage
2. Sign in with your Apple ID
3. Under "Security" → "App-Specific Passwords"
4. Generate a new password for "Notarization"
5. **Save this password immediately** - you won't be able to see it again

### 4. Entitlements Files

You'll need two entitlements files:

**`entitlements.dev-id.plist`** (main app):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

**`entitlements.dev-id.inherit.plist`** (helper apps and nested executables):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
</dict>
</plist>
```

**Note:** Adjust entitlements based on your app's needs. The above are common for Electron apps.

---

## Initial Setup

### Step 1: Verify Your Certificate

Check that your Developer ID certificate is installed:

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

You should see output like:
```
1) ABC123DEF456 "Developer ID Application: Your Name (TEAM_ID)" (CSSMERR_TP_CERT_REVOKED)
```

**Important:** The certificate must NOT be revoked. If you see `CSSMERR_TP_CERT_REVOKED`, you need to install a valid certificate.

### Step 2: Set Environment Variables (Optional but Recommended)

Create a `.env` file or export these variables:

```bash
export APPLE_ID="your-apple-id@example.com"
export APPLE_PASSWORD="your-app-specific-password"
export TEAM_ID="YOUR_TEAM_ID"
export DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
```

**Security Note:** Never commit `.env` files to version control. Add `.env` to your `.gitignore`.

---

## Build Configuration

### Electron-Builder Configuration

For Electron apps using `electron-builder`, configure your `package.json` or `electron-builder.yml`:

**package.json example:**
```json
{
  "build": {
    "appId": "com.yourcompany.yourapp",
    "productName": "Your App Name",
    "mac": {
      "category": "public.app-category.utilities",
      "target": "dmg",
      "hardenedRuntime": true,
      "gatekeeperAssess": true,
      "entitlements": "build/entitlements.dev-id.plist",
      "entitlementsInherit": "build/entitlements.dev-id.inherit.plist",
      "minimumSystemVersion": "12.0",
      "icon": "build/icon.icns"
    },
    "dmg": {
      "sign": false
    }
  }
}
```

**Key settings:**
- `hardenedRuntime: true` - **Required** for notarization
- `gatekeeperAssess: true` - Enables Gatekeeper assessment
- `entitlements` - Path to main app entitlements
- `entitlementsInherit` - Path to helper app entitlements
- `dmg.sign: false` - We'll sign the DMG manually after creation

---

## Building the Signed App

### Step 1: Clean Extended Attributes

macOS extended attributes (especially Finder information) can prevent code signing. Clean them before building:

```bash
# From your project root
find . -type f -not -path "./node_modules/*" -not -path "./dist/*" -not -path "./.git/*" -exec xattr -c {} \; 2>/dev/null || true
```

### Step 2: Build the App Bundle

Build your app without signing first (we'll sign manually):

```bash
# For Electron apps with electron-builder
npx electron-builder --mac dir --config.mac.identity=""
```

This creates the app bundle in `dist/mac-arm64/YourApp.app` (or similar).

### Step 3: Clean the Built App Bundle

Remove extended attributes from the built app:

```bash
APP_PATH="dist/mac-arm64/YourApp.app"

# Remove all extended attributes
xattr -cr "$APP_PATH" 2>/dev/null || true

# Remove specific problematic attributes
find "$APP_PATH" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_PATH" -exec xattr -d com.apple.fileprovider.fpfs#P {} \; 2>/dev/null || true
find "$APP_PATH" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

# Remove Finder metadata files
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true

# Copy app bundle to remove resource forks (if needed)
TEMP_DIR=$(mktemp -d)
CLEAN_APP="$TEMP_DIR/$(basename "$APP_PATH")"
cp -R -X "$APP_PATH" "$CLEAN_APP" 2>/dev/null
xattr -cr "$CLEAN_APP" 2>/dev/null || true
rm -rf "$APP_PATH"
mv "$CLEAN_APP" "$APP_PATH"
rm -rf "$TEMP_DIR"
```

---

## Manual Signing Process

### Critical: Sign in the Correct Order

Components must be signed from the **inside out** - sign nested components before parent components. The order matters!

### Step 1: Sign Libraries and Binaries in Electron Framework

For Electron apps, sign all `.dylib` files and helpers in the Electron Framework:

```bash
APP_PATH="dist/mac-arm64/YourApp.app"
IDENTITY="Developer ID Application: Your Name (TEAM_ID)"

# Sign all .dylib files
find "$APP_PATH/Contents/Frameworks/Electron Framework.framework" -name "*.dylib" -type f | while read -r dylib; do
  codesign --sign "$IDENTITY" \
    --force \
    --timestamp \
    --options runtime \
    "$dylib"
done

# Sign chrome_crashpad_handler
CRASHPAD_HANDLER="$APP_PATH/Contents/Frameworks/Electron Framework.framework/Versions/A/Helpers/chrome_crashpad_handler"
if [ -f "$CRASHPAD_HANDLER" ]; then
  codesign --sign "$IDENTITY" \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "build/entitlements.dev-id.inherit.plist" \
    "$CRASHPAD_HANDLER"
fi

# Sign Electron Framework binary
FRAMEWORK_BINARY="$APP_PATH/Contents/Frameworks/Electron Framework.framework/Versions/A/Electron Framework"
codesign --sign "$IDENTITY" \
  --force \
  --timestamp \
  --options runtime \
  "$FRAMEWORK_BINARY"
```

### Step 2: Sign Helper Apps

Sign all helper apps (they're nested `.app` bundles):

```bash
HELPER_APPS=$(find "$APP_PATH/Contents/Frameworks" -name "*.app" -type d 2>/dev/null || true)

if [ -n "$HELPER_APPS" ]; then
  while IFS= read -r helper; do
    # Remove existing signature
    codesign --remove-signature "$helper" 2>/dev/null || true
    
    # Clean extended attributes
    xattr -cr "$helper" 2>/dev/null || true
    find "$helper" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
    
    # Sign
    codesign --sign "$IDENTITY" \
      --force \
      --timestamp \
      --options runtime \
      --entitlements "build/entitlements.dev-id.inherit.plist" \
      "$helper"
  done <<< "$HELPER_APPS"
fi
```

### Step 3: Sign Framework Binaries

Sign framework binaries (Squirrel, Mantle, ReactiveObjC, etc.):

```bash
FRAMEWORKS=$(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null || true)

if [ -n "$FRAMEWORKS" ]; then
  while IFS= read -r framework; do
    FRAMEWORK_NAME=$(basename "$framework" .framework)
    
    # Sign resources FIRST (before framework binary)
    # Example: Sign ShipIt in Squirrel framework
    SHIPIT="$framework/Versions/A/Resources/ShipIt"
    if [ -f "$SHIPIT" ]; then
      codesign --remove-signature "$SHIPIT" 2>/dev/null || true
      codesign --sign "$IDENTITY" \
        --force \
        --timestamp \
        --options runtime \
        --entitlements "build/entitlements.dev-id.inherit.plist" \
        "$SHIPIT"
    fi
    
    # Now sign the framework binary
    FRAMEWORK_BINARY=$(find "$framework" -name "$FRAMEWORK_NAME" -type f | head -1)
    if [ -f "$FRAMEWORK_BINARY" ]; then
      codesign --remove-signature "$FRAMEWORK_BINARY" 2>/dev/null || true
      codesign --sign "$IDENTITY" \
        --force \
        --timestamp \
        --options runtime \
        "$FRAMEWORK_BINARY"
    fi
  done <<< "$FRAMEWORKS"
fi
```

### Step 4: Sign the Main App Bundle

Finally, sign the main app bundle:

```bash
# Remove existing signature
codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# Final cleanup
xattr -cr "$APP_PATH" 2>/dev/null || true

# Sign the main app bundle
codesign --sign "$IDENTITY" \
  --force \
  --timestamp \
  --options runtime \
  --entitlements "build/entitlements.dev-id.plist" \
  "$APP_PATH"
```

### Step 5: Verify App Bundle Signature

Verify the signature is valid:

```bash
codesign -vvv --deep --strict "$APP_PATH"
```

You should see:
```
dist/mac-arm64/YourApp.app: valid on disk
dist/mac-arm64/YourApp.app: satisfies its Designated Requirement
```

If you see errors, fix them before proceeding.

---

## Creating the DMG

### Step 1: Create DMG from Signed App

Use electron-builder or `hdiutil` to create the DMG:

```bash
# Using electron-builder (recommended)
npx electron-builder --mac dmg \
  --prepackaged="$APP_PATH" \
  --config.dmg.sign=false

# Or using hdiutil (manual method)
DMG_NAME="YourApp-1.0.0-arm64.dmg"
hdiutil create -volname "YourApp" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_NAME"
```

### Step 2: Sign the DMG

Sign the DMG file:

```bash
DMG_PATH="dist/YourApp-1.0.0-arm64.dmg"

codesign --sign "$IDENTITY" \
  --options runtime \
  "$DMG_PATH"
```

### Step 3: Verify DMG Signature

```bash
codesign -vvv "$DMG_PATH"
```

You should see:
```
dist/YourApp-1.0.0-arm64.dmg: valid on disk
dist/YourApp-1.0.0-arm64.dmg: satisfies its Designated Requirement
```

---

## Submitting for Notarization

### Method 1: Command Line (Recommended)

Use `xcrun notarytool` (macOS 13+):

```bash
# Submit for notarization
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# The --wait flag waits for completion (typically 5-15 minutes)
# You'll see status updates and final result
```

**Alternative:** Submit without waiting:

```bash
# Submit without waiting
SUBMISSION_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID" 2>&1)

# Extract submission ID
SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)

echo "Submission ID: $SUBMISSION_ID"

# Check status later
xcrun notarytool info "$SUBMISSION_ID" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID"

# Wait for completion
xcrun notarytool wait "$SUBMISSION_ID" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID"
```

### Method 2: Apple Developer Portal

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Navigate to "Notarization" section
3. Upload your DMG or zip file
4. Wait for processing (5-15 minutes)
5. Check status in the portal

### Step 2: Check Notarization Status

If notarization fails, check the logs:

```bash
xcrun notarytool log "$SUBMISSION_ID" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID"
```

This shows detailed error messages about what failed.

### Step 3: View Submission History

View all recent submissions:

```bash
xcrun notarytool history \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID"
```

---

## Stapling the Notarization Ticket

After successful notarization, you **must** staple the ticket to your app and DMG. This allows users to install without an internet connection.

### Step 1: Staple to App Bundle

```bash
xcrun stapler staple "$APP_PATH"
```

### Step 2: Staple to DMG

```bash
xcrun stapler staple "$DMG_PATH"
```

### Step 3: Verify Stapling

```bash
# Verify app bundle
xcrun stapler validate "$APP_PATH"

# Verify DMG
xcrun stapler validate "$DMG_PATH"
```

Both should show:
```
The validate action worked!
```

---

## Verification and Testing

### Step 1: Verify Code Signatures

```bash
# Verify app bundle
codesign -vvv --deep --strict "$APP_PATH"

# Verify DMG
codesign -vvv "$DMG_PATH"
```

### Step 2: Verify Notarization Stapling

```bash
xcrun stapler validate "$DMG_PATH"
xcrun stapler validate "$APP_PATH"
```

### Step 3: Test with Gatekeeper

```bash
# Test DMG
spctl -a -vv -t install "$DMG_PATH"

# Should show:
# YourApp.dmg: accepted
# source=Notarized Developer ID
```

### Step 4: Test Installation

1. Open the DMG: `open "$DMG_PATH"`
2. Drag the app to Applications
3. Try to launch the app
4. Gatekeeper should accept it without warnings

---

## Troubleshooting

### Issue: "resource fork, Finder information, or similar detritus not allowed"

**Cause:** Extended attributes (especially Finder information) prevent code signing.

**Solution:**
```bash
# Aggressively remove all extended attributes
xattr -cr "$APP_PATH"
find "$APP_PATH" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_PATH" -exec xattr -d com.apple.fileprovider.fpfs#P {} \; 2>/dev/null || true
find "$APP_PATH" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true

# Copy app bundle to remove resource forks
TEMP_DIR=$(mktemp -d)
cp -R -X "$APP_PATH" "$TEMP_DIR/$(basename "$APP_PATH")"
rm -rf "$APP_PATH"
mv "$TEMP_DIR/$(basename "$APP_PATH")" "$APP_PATH"
rm -rf "$TEMP_DIR"
```

### Issue: "The signature of the binary is invalid"

**Causes:**
- Signing order incorrect (must sign nested components first)
- Extended attributes still present
- Missing hardened runtime
- Missing entitlements

**Solution:**
1. Verify signing order (libraries → helpers → frameworks → main app)
2. Clean extended attributes (see above)
3. Ensure `--options runtime` is included in all codesign commands
4. Verify entitlements files exist and are correct

### Issue: "a sealed resource is missing or invalid"

**Cause:** A nested component was modified after its parent was signed.

**Solution:** Sign resources (like `ShipIt`) **before** signing the framework binary that contains them.

### Issue: "code object is not signed at all"

**Cause:** The component was never signed, or signature was removed.

**Solution:** Ensure you signed all components in the correct order.

### Issue: Notarization fails with "Invalid" status

**Common causes:**
1. Missing signatures on nested components
2. Invalid signatures (signing order issue)
3. Missing hardened runtime
4. Missing or incorrect entitlements
5. Missing secure timestamps (use `--timestamp` flag)

**Solution:**
1. Check notarization logs: `xcrun notarytool log <SUBMISSION_ID> ...`
2. Fix all errors shown in the logs
3. Rebuild, re-sign, and resubmit

### Issue: Build hangs at "installing native dependencies"

**Cause:** electron-builder is rebuilding native dependencies, which can take 5-10 minutes.

**Solution:** This is normal. Wait for it to complete. Subsequent builds will be faster.

### Issue: Build script hangs during "Cleaning extended attributes"

**Cause:** Running `xattr -cr .` recursively on large directories (especially `node_modules`) can take a very long time or appear to hang.

**Solution:** Skip large directories when cleaning extended attributes:
```bash
# Skip node_modules, dist, and .git directories
find . -type f -not -path "./node_modules/*" -not -path "./dist/*" -not -path "./.git/*" -exec xattr -c {} \; 2>/dev/null || true
```

### Issue: Package.json backup file left behind after interrupted build

**Cause:** Build scripts that temporarily modify `package.json` create a backup file. If the process is interrupted, the backup may not be restored.

**Solution:** Check for and restore backup files:
```bash
# Check for package.json.backup
if [ -f "package.json.backup" ]; then
  mv package.json.backup package.json
  echo "Restored package.json from backup"
fi
```

**Prevention:** Always use `set -e` error handling and ensure cleanup happens in `trap` handlers or `finally` blocks.

### Issue: Codesign shows warnings but signature verification passes

**Cause:** Codesign may output warnings (like "resource fork" warnings) but still successfully create a signature. The warnings can be misleading.

**Solution:** Always verify the signature separately, don't rely on exit codes alone:
```bash
# Sign with filtering warnings
codesign --sign "$IDENTITY" --force --timestamp --options runtime "$APP_PATH" 2>&1 | grep -v "resource fork" || true

# Verify signature separately
if codesign -vv "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
  echo "✅ Signature is valid (warnings can be ignored)"
else
  echo "❌ Signature verification failed"
fi
```

### Issue: Helper apps show verification warnings but are actually signed

**Cause:** Verification scripts may check incorrectly or codesign output may be misleading. The actual signature may be valid.

**Solution:** Always double-check with `codesign -vv` directly:
```bash
# Check helper app signature directly
codesign -vv "$HELPER_APP_PATH"

# Should show:
# Helper.app: valid on disk
# Helper.app: satisfies its Designated Requirement
```

If it shows "valid on disk", the signature is correct despite any warnings in your verification script.

### Issue: Extended attributes reappear after cleaning

**Cause:** macOS may automatically add extended attributes (like Finder information) when files are accessed or copied.

**Solution:** 
1. Use `cp -R -X` to copy without extended attributes
2. Clean immediately before signing, not earlier in the process
3. Copy the app bundle to a clean location if needed:
```bash
TEMP_DIR=$(mktemp -d)
CLEAN_APP="$TEMP_DIR/$(basename "$APP_PATH")"
cp -R -X "$APP_PATH" "$CLEAN_APP"
xattr -cr "$CLEAN_APP" 2>/dev/null || true
rm -rf "$APP_PATH"
mv "$CLEAN_APP" "$APP_PATH"
rm -rf "$TEMP_DIR"
```

### Issue: "replacing existing signature" warnings

**Cause:** You're signing a component that already has a signature. This is normal when re-signing.

**Solution:** These warnings are harmless. You can filter them:
```bash
codesign --sign "$IDENTITY" --force "$APP_PATH" 2>&1 | grep -v "replacing existing signature" || true
```

**Note:** Always use `--force` when re-signing. Without it, codesign will fail if a signature already exists.

### Issue: Verification script shows errors but manual verification passes

**Cause:** Verification scripts may use overly strict checks or check in the wrong order. Manual verification with `codesign -vv` is the authoritative source.

**Solution:** When in doubt, verify manually:
```bash
# Manual verification (authoritative)
codesign -vvv --deep --strict "$APP_PATH"

# Check specific component
codesign -vvv "$APP_PATH/Contents/Frameworks/SomeFramework.framework"

# Check if signed at all
codesign -d -vv "$APP_PATH" 2>&1 | grep "Authority="
```

### Issue: Notarization fails with "The signature of the binary is invalid" for specific components

**Cause:** A component was signed incorrectly, or the signing order was wrong, or extended attributes weren't cleaned.

**Solution:**
1. Check notarization logs to identify the specific component
2. Remove signature from that component: `codesign --remove-signature "$COMPONENT"`
3. Clean extended attributes: `xattr -cr "$COMPONENT"`
4. Re-sign in correct order (nested components first)
5. Verify signature: `codesign -vv "$COMPONENT"`

### Issue: Script output is being filtered/hidden

**Cause:** Using `grep` filters or output redirection may hide important error messages.

**Solution:** 
1. Remove or comment out grep filters temporarily to see full output
2. Use `tee` to capture output to a file while still seeing it:
```bash
codesign --sign "$IDENTITY" "$APP_PATH" 2>&1 | tee /tmp/signing-output.log
```

### Issue: Cannot find app bundle after build

**Cause:** electron-builder may create app bundles in different locations (`dist/mac/`, `dist/mac-arm64/`, `dist/mac-x64/`) depending on architecture.

**Solution:** Check all possible locations:
```bash
# Search for app bundle
find dist -name "*.app" -type d | head -5

# Or check common locations
ls -la dist/mac*/YourApp.app 2>/dev/null
ls -la dist/*/YourApp.app 2>/dev/null
```

Update your script to check multiple patterns:
```bash
APP_PATTERNS=(
  "dist/mac/YourApp.app"
  "dist/mac-arm64/YourApp.app"
  "dist/mac-x64/YourApp.app"
)

APP_PATH=""
for pattern in "${APP_PATTERNS[@]}"; do
  if [ -d "$pattern" ]; then
    APP_PATH="$pattern"
    break
  fi
done
```

### Issue: "code has no resources but signature indicates they must be present"

**Cause:** This warning appears for helper apps that were signed with entitlements but don't actually need them, or the signature format doesn't match expectations.

**Solution:** This is often a harmless warning. Verify the signature is actually valid:
```bash
codesign -vv "$HELPER_APP"
# If it shows "valid on disk", the warning can be ignored
```

If notarization fails specifically for this component, try signing without entitlements (if the component doesn't need them).

### Issue: Using --deep flag causes signing to fail

**Cause:** The `--deep` flag tries to sign everything recursively, which can conflict with manually signed nested components and cause issues with resource forks.

**Solution:** Sign components manually from the inside out instead of using `--deep`. The `--deep` flag is deprecated and not recommended:
```bash
# DON'T do this:
codesign --sign "$IDENTITY" --deep "$APP_PATH"  # ❌ Don't use --deep

# DO this instead:
# Sign nested components first, then main app bundle
# (Follow the signing order in this guide)
```

### Issue: SetFile command not found

**Cause:** `SetFile` is part of Xcode Command Line Tools and may not be installed.

**Solution:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

Or skip SetFile usage - it's optional. Extended attribute removal with `xattr` is usually sufficient.

### Issue: Notarization succeeds but stapling fails

**Cause:** The notarization ticket may not be fully propagated, or there's a network issue accessing Apple's servers.

**Solution:**
1. Wait a few minutes after notarization completes
2. Try stapling again
3. Check your internet connection
4. Verify notarization was actually successful:
```bash
xcrun notarytool history --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$TEAM_ID"
```

If stapling consistently fails, you can still distribute - Gatekeeper will check online, but users need internet connection on first run.

### Issue: Build takes a very long time even after dependencies are installed

**Cause:** electron-builder rebuilds native dependencies on every build, or extended attribute cleaning is slow.

**Solution:**
1. For native dependencies: This is normal for first build. Subsequent builds cache the results.
2. For extended attributes: Skip large directories (see "Build hangs during extended attributes" above)
3. Consider parallel builds or build caching if using CI/CD

---

## Automation Scripts

### Complete Build and Notarization Script

Here's a complete bash script template you can adapt:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
APP_NAME="YourApp"
APP_VERSION="1.0.0"
APP_ID="com.yourcompany.yourapp"
TEAM_ID="YOUR_TEAM_ID"
APPLE_ID="${APPLE_ID:-your-email@example.com}"
APPLE_PASSWORD="${APPLE_PASSWORD:-your-app-specific-password}"
IDENTITY="Developer ID Application: Your Name ($TEAM_ID)"

# Build the app
echo "Building app..."
npx electron-builder --mac dir --config.mac.identity=""

APP_PATH="dist/mac-arm64/${APP_NAME}.app"

# Clean extended attributes
echo "Cleaning extended attributes..."
xattr -cr "$APP_PATH" 2>/dev/null || true
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true

# Sign all components (libraries, helpers, frameworks, main app)
echo "Signing app bundle..."
# ... (use signing code from "Manual Signing Process" section) ...

# Verify signature
codesign -vvv --deep --strict "$APP_PATH"

# Create DMG
echo "Creating DMG..."
npx electron-builder --mac dmg --prepackaged="$APP_PATH" --config.dmg.sign=false

DMG_PATH="dist/${APP_NAME}-${APP_VERSION}-arm64.dmg"

# Sign DMG
codesign --sign "$IDENTITY" --options runtime "$DMG_PATH"

# Submit for notarization
echo "Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# Staple
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler staple "$DMG_PATH"

# Verify
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t install "$DMG_PATH"

echo "✅ Complete! Notarized DMG: $DMG_PATH"
```

---

## Checklist

Use this checklist for each release:

- [ ] Developer ID certificate installed and valid
- [ ] App-specific password created and saved
- [ ] Entitlements files created and configured
- [ ] Extended attributes cleaned from source
- [ ] App bundle built
- [ ] Extended attributes cleaned from built app
- [ ] All libraries signed (e.g., .dylib files)
- [ ] All helper apps signed
- [ ] All frameworks signed (resources before binaries)
- [ ] Main app bundle signed
- [ ] App bundle signature verified
- [ ] DMG created
- [ ] DMG signed
- [ ] DMG signature verified
- [ ] Submitted for notarization
- [ ] Notarization status: Accepted
- [ ] Notarization ticket stapled to app bundle
- [ ] Notarization ticket stapled to DMG
- [ ] Stapling verified
- [ ] Gatekeeper acceptance verified
- [ ] Installation tested on clean system

---

## Additional Resources

- [Apple's Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Resolving Common Notarization Issues](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/resolving_common_notarization_issues)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)

---

## Quick Reference: Common Commands

```bash
# Find Developer ID certificate
security find-identity -v -p codesigning | grep "Developer ID"

# Clean extended attributes
xattr -cr /path/to/app

# Sign a binary
codesign --sign "Developer ID Application: Name (TEAM_ID)" \
  --force \
  --timestamp \
  --options runtime \
  --entitlements entitlements.plist \
  /path/to/binary

# Verify signature
codesign -vvv /path/to/app

# Submit for notarization
xcrun notarytool submit file.dmg \
  --apple-id email@example.com \
  --password app-specific-password \
  --team-id TEAM_ID \
  --wait

# Check notarization status
xcrun notarytool history \
  --apple-id email@example.com \
  --password app-specific-password \
  --team-id TEAM_ID

# Staple ticket
xcrun stapler staple file.dmg

# Verify stapling
xcrun stapler validate file.dmg

# Test with Gatekeeper
spctl -a -vv -t install file.dmg
```

---

## Notes

- **Hardened Runtime** is REQUIRED for notarization
- **Secure Timestamps** (`--timestamp`) are required for notarization
- **Signing Order** matters - always sign from inside out
- **Extended Attributes** must be cleaned before signing
- Notarization typically takes **5-15 minutes**
- The DMG can be tested locally before notarization, but Gatekeeper will show warnings
- After notarization and stapling, the DMG will pass Gatekeeper without warnings

---

**Last Updated:** January 2025
**Tested With:** macOS 13+, Xcode Command Line Tools, electron-builder 25+
