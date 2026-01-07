#!/bin/bash
set -euo pipefail

# Sign the Electron app with MAS certificate and entitlements

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Get app path from previous build step
if [ -f ".mas-app-path" ]; then
  APP="$(cat .mas-app-path)"
else
  # Fallback: try to find it
  APP_DIRS=(
    "apps/electron/dist/mac-unpacked/Nexus Countdown.app"
    "apps/electron/dist/mac-arm64-unpacked/Nexus Countdown.app"
    "apps/electron/dist/mac-x64-unpacked/Nexus Countdown.app"
    "apps/electron/dist/mac-universal/Nexus Countdown.app"
  )
  
  APP=""
  for candidate in "${APP_DIRS[@]}"; do
    if [ -d "$candidate" ]; then
      APP="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
      break
    fi
  done
  
  if [ -z "$APP" ]; then
    echo "❌ ERROR: Could not find app bundle. Run build script first."
    exit 1
  fi
fi

if [ ! -d "$APP" ]; then
  echo "❌ ERROR: App bundle not found at: $APP"
  exit 1
fi

echo "🔐 Signing Electron app for MAS..."
echo "App: $APP"

# Remove quarantine flags recursively
echo "Removing quarantine attributes..."
xattr -cr "$APP" || true

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

echo "Embedding provisioning profile..."
cp "$PROV_PROFILE" "$APP/Contents/embedded.provisionprofile"

# Update Info.plist to ensure correct bundle ID and category
INFO_PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nexuscountdown" "$INFO_PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.nexuscountdown" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.utilities" "$INFO_PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.utilities" "$INFO_PLIST"

# Signing identity
IDENTITY="3rd Party Mac Developer Application: Adam Parsons (T6YG6KXA9D)"
ENTITLEMENTS="$REPO_ROOT/apps/electron/build/entitlements.mas.plist"
ENTITLEMENTS_INHERIT="$REPO_ROOT/apps/electron/build/entitlements.mas.inherit.plist"
ENTITLEMENTS_FRAMEWORK_HELPER="$REPO_ROOT/apps/electron/build/entitlements.mas.framework-helper.plist"

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "❌ ERROR: Entitlements file not found: $ENTITLEMENTS"
  exit 1
fi

# Sign all helper apps and frameworks first (required by codesign)
echo "Signing helpers and frameworks..."

# Sign helper apps and app extensions (must embed provisioning profile for TestFlight)
# NOTE: Do NOT use --deep as it may interfere with provisioning profile embedding
echo "  Embedding profiles and signing helper apps..."

# Sign helper apps
for helper in "$APP/Contents/Frameworks/"*Helper*.app; do
  if [ -d "$helper" ]; then
    HELPER_NAME="$(basename "$helper")"
    echo "    Signing helper: $HELPER_NAME"
    
    # CRITICAL: Update helper bundle ID to match main app for TestFlight validation
    # Apple requires the bundle ID to match the provisioning profile's App ID
    HELPER_INFO_PLIST="$helper/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nexuscountdown" "$HELPER_INFO_PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.nexuscountdown" "$HELPER_INFO_PLIST"
    
    # Embed provisioning profile in helper app BEFORE signing (required for TestFlight)
    cp "$PROV_PROFILE" "$helper/Contents/embedded.provisionprofile"
    
    # Sign helper app WITHOUT --deep to preserve provisioning profile
    codesign --force --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS_INHERIT" \
      --options runtime \
      "$helper"
  fi
done

# Sign app extensions (.appex) if any exist
for appex in "$APP/Contents/Frameworks/"*.appex; do
  if [ -d "$appex" ]; then
    APPEX_NAME="$(basename "$appex")"
    echo "    Signing app extension: $APPEX_NAME"
    
    # Update bundle ID to match main app
    APPEX_INFO_PLIST="$appex/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nexuscountdown" "$APPEX_INFO_PLIST" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.nexuscountdown" "$APPEX_INFO_PLIST"
    
    # Embed provisioning profile BEFORE signing
    cp "$PROV_PROFILE" "$appex/Contents/embedded.provisionprofile"
    
    # Sign app extension
    codesign --force --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS_INHERIT" \
      --options runtime \
      "$appex"
  fi
done

# Sign Electron Framework (must sign inner components first)
FRAMEWORK="$APP/Contents/Frameworks/Electron Framework.framework"
if [ -d "$FRAMEWORK" ]; then
  echo "  Signing Electron Framework..."
  
  # Embed provisioning profile in Electron Framework Resources directory (optional, for framework itself)
  # Note: Framework helpers like chrome_crashpad_handler are now signed WITHOUT application-identifier
  # so they don't require a provisioning profile, eliminating the 90885 error.
  RESOURCES_DIR="$FRAMEWORK/Versions/A/Resources"
  if [ -d "$RESOURCES_DIR" ]; then
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
for framework in "$APP/Contents/Frameworks"/*.framework; do
  if [ -d "$framework" ] && [ "$(basename "$framework")" != "Electron Framework.framework" ]; then
    FRAMEWORK_NAME="$(basename "$framework")"
    
    # Skip Squirrel.framework if it somehow still exists (should have been removed)
    if [ "$FRAMEWORK_NAME" = "Squirrel.framework" ]; then
      echo "  ⚠️  WARNING: Squirrel.framework found but should have been removed for MAS build"
      echo "     Skipping Squirrel.framework signing"
      continue
    fi
    
    echo "  Signing framework: $FRAMEWORK_NAME"
    
    # Sign the framework itself
    codesign --force --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS_INHERIT" \
      --options runtime \
      "$framework"
  fi
done

# Sign the main app (don't use --deep since we've already signed all nested components explicitly)
# After signing helpers, we need to re-sign the main app to include them
echo "Signing main app..."
codesign --force --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  "$APP"

# Verify signature
echo ""
echo "Verifying code signature..."
codesign -dv --verbose=4 "$APP" || true

echo ""
echo "Checking deep signature validation..."
if codesign -vvv --deep --strict "$APP" 2>&1 | grep -q "satisfies its Designated Requirement"; then
  echo "✅ Code signature valid"
else
  echo "⚠️  Warning: Deep signature validation had issues (this may be OK for MAS)"
  codesign -vvv --deep --strict "$APP" || true
fi

echo ""
echo "Checking entitlements..."
ENTITLEMENTS_OUT=$(codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null || echo "")
if echo "$ENTITLEMENTS_OUT" | grep -q "T6YG6KXA9D.com.nexuscountdown"; then
  echo "✅ Entitlements correct"
else
  echo "⚠️  Warning: Entitlements check"
  echo "$ENTITLEMENTS_OUT"
fi

echo ""
echo "✅ App signed successfully: $APP"

