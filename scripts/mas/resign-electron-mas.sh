#!/bin/bash
set -euo pipefail

# Re-sign the Electron MAS app and all nested bundles after provisioning profiles are embedded

APP="$1"

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "❌ ERROR: App bundle not found: $APP"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IDENTITY="3rd Party Mac Developer Application: Adam Parsons (T6YG6KXA9D)"
ENTITLEMENTS="$REPO_ROOT/apps/electron/build/entitlements.mas.plist"
ENTITLEMENTS_INHERIT="$REPO_ROOT/apps/electron/build/entitlements.mas.inherit.plist"
ENTITLEMENTS_FRAMEWORK_HELPER="$REPO_ROOT/apps/electron/build/entitlements.mas.framework-helper.plist"

# Get provisioning profile using detection script
PROV_PROFILE=""
if [ -f "$REPO_ROOT/scripts/mas/detect-electron-profile.js" ]; then
  PROV_PROFILE=$(node "$REPO_ROOT/scripts/mas/detect-electron-profile.js" 2>/dev/null || echo "")
fi
if [ -z "$PROV_PROFILE" ] || [ ! -f "$PROV_PROFILE" ]; then
  echo "❌ ERROR: Could not detect provisioning profile"
  echo "   Tried: node scripts/mas/detect-electron-profile.js"
  echo "   Fallback: Check that cert/Nexus_Countdown.provisionprofile exists"
  exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "❌ ERROR: Entitlements file not found: $ENTITLEMENTS"
  exit 1
fi

if [ ! -f "$ENTITLEMENTS_INHERIT" ]; then
  echo "❌ ERROR: Inherit entitlements file not found: $ENTITLEMENTS_INHERIT"
  exit 1
fi

echo "🔐 Re-signing Electron app for MAS..."
echo "   App: $(basename "$APP")"
echo ""

# Remove quarantine flags recursively
echo "   Removing quarantine attributes..."
xattr -cr "$APP" || true

# Ensure helper bundle IDs match main app (required for TestFlight)
MAIN_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
echo "   Main app bundle ID: $MAIN_BUNDLE_ID"

# Sign helper apps first
echo ""
echo "   Signing helper apps..."
for helper in "$APP/Contents/Frameworks/"*Helper*.app; do
  if [ -d "$helper" ]; then
    HELPER_NAME="$(basename "$helper")"
    
    # Update helper bundle ID to match main app (required for TestFlight)
    HELPER_INFO_PLIST="$helper/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $MAIN_BUNDLE_ID" "$HELPER_INFO_PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $MAIN_BUNDLE_ID" "$HELPER_INFO_PLIST"
    
    echo "     Signing: $HELPER_NAME"
    codesign --force --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS_INHERIT" \
      --options runtime \
      "$helper"
  fi
done

# Sign Electron Framework (must sign inner components first)
FRAMEWORK="$APP/Contents/Frameworks/Electron Framework.framework"
if [ -d "$FRAMEWORK" ]; then
  echo ""
  echo "   Signing Electron Framework..."
  
  # Embed provisioning profile in Electron Framework Resources directory (optional, for framework itself)
  # Note: Framework helpers like chrome_crashpad_handler are now signed WITHOUT application-identifier
  # so they don't require a provisioning profile, eliminating the 90885 error.
  RESOURCES_DIR="$FRAMEWORK/Versions/A/Resources"
  if [ -d "$RESOURCES_DIR" ] && [ -f "$PROV_PROFILE" ]; then
    # Profile embedding kept for compatibility, but not strictly required for helpers anymore
    cp "$PROV_PROFILE" "$RESOURCES_DIR/embedded.provisionprofile" 2>/dev/null || true
  fi
  
  # Sign libraries inside the framework
  if [ -d "$FRAMEWORK/Versions/A/Libraries" ]; then
    for lib in "$FRAMEWORK/Versions/A/Libraries"/*.dylib; do
      if [ -f "$lib" ]; then
        codesign --force --sign "$IDENTITY" \
          --entitlements "$ENTITLEMENTS_INHERIT" \
          --options runtime \
          "$lib"
      fi
    done
  fi
  
  # Sign helpers inside the framework
  # NOTE: Framework helpers (like chrome_crashpad_handler) are signed WITHOUT application-identifier
  # to avoid requiring a separate provisioning profile. They still get team-identifier and app-sandbox
  # entitlements to remain MAS-compliant, but without the application-identifier that triggers 90885.
  if [ -d "$FRAMEWORK/Versions/A/Helpers" ]; then
    for helper_bin in "$FRAMEWORK/Versions/A/Helpers"/*; do
      if [ -f "$helper_bin" ] && [ -x "$helper_bin" ]; then
        codesign --force --sign "$IDENTITY" \
          --entitlements "$ENTITLEMENTS_FRAMEWORK_HELPER" \
          --options runtime \
          "$helper_bin"
      fi
    done
  fi
  
  # Sign the framework itself
  codesign --force --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS_INHERIT" \
    --options runtime \
    "$FRAMEWORK"
fi

# Sign other frameworks (Mantle, ReactiveObjC, etc.)
# NOTE: Squirrel.framework should NOT be present for MAS builds (removed in build step)
echo ""
echo "   Signing other frameworks..."
for framework in "$APP/Contents/Frameworks"/*.framework; do
  if [ -d "$framework" ] && [ "$(basename "$framework")" != "Electron Framework.framework" ]; then
    FRAMEWORK_NAME="$(basename "$framework")"
    
    # Skip Squirrel.framework if it somehow still exists (should have been removed)
    if [ "$FRAMEWORK_NAME" = "Squirrel.framework" ]; then
      echo "     ⚠️  WARNING: Squirrel.framework found but should have been removed for MAS build"
      echo "     Skipping Squirrel.framework signing"
      continue
    fi
    
    # Sign the framework itself
    codesign --force --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS_INHERIT" \
      --options runtime \
      "$framework"
  fi
done

# Sign the main app (don't use --deep since we've already signed all nested components explicitly)
echo ""
echo "   Signing main app..."
codesign --force --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  "$APP"

echo ""
echo "✅ App re-signed successfully"

# Verify signature
echo ""
echo "   Verifying code signature..."
if codesign -vvv --deep --strict "$APP" 2>&1 | grep -q "satisfies its Designated Requirement"; then
  echo "   ✅ Code signature valid"
else
  echo "   ⚠️  Code signature verification had warnings (this may be OK)"
  codesign -vvv --deep --strict "$APP" 2>&1 | head -10 || true
fi

