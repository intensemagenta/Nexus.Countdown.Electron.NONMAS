# Electron MAS Build Pipeline

This document describes the complete Mac App Store (MAS) build pipeline for the Electron app.

## Overview

The pipeline ensures that all nested executables have proper provisioning profiles embedded, resolving TestFlight validation error 90885.

## Quick Start

Run the complete pipeline from the repository root:

```bash
npm run mas:electron
```

This single command will:
1. Build the Electron app for MAS (universal binary: arm64 + x86_64)
2. Embed provisioning profiles into main app and all helper apps
3. Sign the app and all nested bundles with MAS certificate
4. Create a signed .pkg installer
5. Verify that all bundles have matching provisioning profiles

## Pipeline Steps

### 1. Build (`build:electron:mas`)

Builds the Electron app directory without signing:

```bash
npm run build:electron:mas
```

- Uses `electron-builder --mac dir` with universal binary (x64 + arm64)
- Output: `apps/electron/dist/mac/Nexus Countdown.app` (unsigned)
- Signing is disabled during build (`CSC_IDENTITY_AUTO_DISCOVERY=false`)

### 2. Embed Profiles (`postbuild:electron:mas`)

Embeds provisioning profiles into the main app and all helper apps:

```bash
npm run postbuild:electron:mas
```

- Locates the built app bundle automatically
- Finds and validates the provisioning profile (`cert/Nexus_Countdown.provisionprofile`)
- Embeds profile into:
  - Main app: `Contents/embedded.provisionprofile`
  - All helper apps: `Contents/Frameworks/*Helper*.app/Contents/embedded.provisionprofile`

### 3. Package (`pkg:electron:mas`)

Creates a signed .pkg installer:

```bash
npm run pkg:electron:mas
```

- Uses `productbuild` with MAS installer certificate
- Output: `dist/mas/com.nexuscountdown.pkg`
- Signed with: `3rd Party Mac Developer Installer: Adam Parsons (T6YG6KXA9D)`

### 4. Verify (`verify:electron:mas`)

Comprehensive verification of the MAS build:

```bash
npm run verify:electron:mas
```

Checks:
- ✅ All bundles with application identifiers have embedded provisioning profiles
- ✅ Application identifiers in signatures match provisioning profiles
- ✅ Bundle IDs match main app (required for TestFlight)
- ✅ Code signatures are valid
- ✅ Entitlements are correct

## Key Scripts

### Helper Scripts

- `scripts/mas/paths-electron.js` - Locates the MAS app bundle
- `scripts/mas/detect-electron-profile.js` - Finds and validates provisioning profile
- `scripts/mas/embed-electron-profiles.sh` - Embeds profiles into all bundles
- `scripts/mas/resign-electron-mas.sh` - Re-signs app and nested bundles
- `scripts/mas/pkg-electron-mas.sh` - Creates signed .pkg installer
- `scripts/mas/verify-electron-mas.js` - Comprehensive verification

## Configuration

### App Bundle ID
- **Bundle ID**: `com.nexuscountdown`
- **Team ID**: `T6YG6KXA9D`
- **App Identifier**: `T6YG6KXA9D.com.nexuscountdown`

### Certificates
- **Application**: `3rd Party Mac Developer Application: Adam Parsons (T6YG6KXA9D)`
- **Installer**: `3rd Party Mac Developer Installer: Adam Parsons (T6YG6KXA9D)`

### Provisioning Profile
- **Location**: `cert/Nexus_Countdown.provisionprofile`
- **App ID**: `T6YG6KXA9D.com.nexuscountdown`
- **Type**: Mac App Store Distribution

### Entitlements
- **Main app**: `apps/electron/build/entitlements.mas.plist`
- **Helper apps**: `apps/electron/build/entitlements.mas.inherit.plist`

## Output Files

After running `npm run mas:electron`:

- **App bundle**: `apps/electron/dist/mac/Nexus Countdown.app` (signed, with embedded profiles)
- **Package**: `dist/mas/com.nexuscountdown.pkg` (signed installer)

## Troubleshooting

### TestFlight Error 90885

If you see this error:
```
Cannot be used with TestFlight because the executable "${executable}" in bundle "${bundle}" 
is missing a provisioning profile but has an application identifier in its signature.
```

**Solution**: Run `npm run verify:electron:mas` to identify which bundles are missing profiles. The pipeline should automatically fix this, but if it persists:

1. Ensure the provisioning profile exists at `cert/Nexus_Countdown.provisionprofile`
2. Check that helper bundle IDs match the main app (`com.nexuscountdown`)
3. Re-run the full pipeline: `npm run mas:electron`

### Build Fails with Signing Error

If electron-builder fails during build with signing errors:

- The build script disables automatic signing (`CSC_IDENTITY_AUTO_DISCOVERY=false`)
- Signing happens manually in the `postbuild:electron:mas` step
- Ensure certificates are installed in your keychain

### Verification Fails

If verification fails:

1. Check which bundles are missing profiles (shown in verification output)
2. Ensure the provisioning profile is valid: `node scripts/mas/detect-electron-profile.js`
3. Re-run the embed step: `npm run postbuild:electron:mas`

## Files Modified by Pipeline

The pipeline modifies these files in the app bundle:

- `Contents/embedded.provisionprofile` (main app)
- `Contents/Frameworks/*Helper*.app/Contents/embedded.provisionprofile` (helper apps)
- `Contents/Frameworks/*Helper*.app/Contents/Info.plist` (bundle IDs updated to match main app)
- Code signatures on all bundles and frameworks

## Testing

To test the pipeline end-to-end:

```bash
# Clean previous builds (optional)
rm -rf apps/electron/dist/mac*
rm -rf dist/mas

# Run full pipeline
npm run mas:electron

# Verify output
npm run verify:electron:mas
```

All verification checks should pass with "✅ VERIFICATION PASSED".

