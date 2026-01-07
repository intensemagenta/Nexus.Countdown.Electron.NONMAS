#!/bin/bash
set -euo pipefail

# Properly verify helper app provisioning profiles for TestFlight

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_PATH="$REPO_ROOT/dist/mas/com.nexuscountdown.pkg"
EXPAND_DIR="/tmp/verify_helper_profiles_$$"

if [ ! -f "$PKG_PATH" ]; then
  echo "❌ PKG not found: $PKG_PATH"
  exit 1
fi

echo "🔍 Verifying helper app provisioning profiles (TestFlight validation)..."
echo ""

trap "rm -rf '$EXPAND_DIR'" EXIT

pkgutil --expand "$PKG_PATH" "$EXPAND_DIR" >/dev/null 2>&1
cd "$EXPAND_DIR/com.nexuscountdown.pkg"
cat Payload | gunzip | cpio -i -d >/dev/null 2>&1

APP_PATH="Nexus Countdown.app"
FULL_APP="$EXPAND_DIR/com.nexuscountdown.pkg/$APP_PATH"

if [ ! -d "$FULL_APP" ]; then
  echo "❌ App bundle not found"
  exit 1
fi

# Get main app provisioning profile App ID
MAIN_PROV="$FULL_APP/Contents/embedded.provisionprofile"
if [ ! -f "$MAIN_PROV" ]; then
  echo "❌ Main app provisioning profile missing"
  exit 1
fi

MAIN_PROV_APP_ID=$(security cms -D -i "$MAIN_PROV" 2>/dev/null | plutil -p - | grep -A 10 "Entitlements" | grep "application-identifier" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
echo "Main app profile App ID: $MAIN_PROV_APP_ID"
echo ""

HELPERS=(
  "Nexus Countdown Helper.app"
  "Nexus Countdown Helper (Plugin).app"
  "Nexus Countdown Helper (Renderer).app"
  "Nexus Countdown Helper (GPU).app"
)

FAILED=0
PASSED=0

for helper in "${HELPERS[@]}"; do
  HELPER_PATH="$FULL_APP/Contents/Frameworks/$helper"
  
  if [ ! -d "$HELPER_PATH" ]; then
    echo "⚠️  $helper: Not found"
    continue
  fi
  
  HELPER_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$HELPER_PATH/Contents/Info.plist" 2>/dev/null || echo "")
  HELPER_PROV="$HELPER_PATH/Contents/embedded.provisionprofile"
  
  echo "=== $helper ==="
  echo "  Bundle ID: $HELPER_BUNDLE_ID"
  
  if [ ! -f "$HELPER_PROV" ]; then
    echo "  ❌ FAIL: Provisioning profile file MISSING"
    ((FAILED++))
    continue
  fi
  
  echo "  ✅ Provisioning profile file exists"
  
  # Check if profile App ID matches helper bundle ID
  HELPER_PROV_APP_ID=$(security cms -D -i "$HELPER_PROV" 2>/dev/null | plutil -p - | grep -A 10 "Entitlements" | grep "application-identifier" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
  
  # Check if the profile App ID matches what would be expected for this helper
  # Expected: T6YG6KXA9D.com.nexuscountdown (main app) OR T6YG6KXA9D.$HELPER_BUNDLE_ID
  EXPECTED_MAIN="T6YG6KXA9D.com.nexuscountdown"
  EXPECTED_HELPER="T6YG6KXA9D.$HELPER_BUNDLE_ID"
  
  echo "  Profile App ID in profile: $HELPER_PROV_APP_ID"
  echo "  Expected (main app): $EXPECTED_MAIN"
  echo "  Expected (helper): $EXPECTED_HELPER"
  
  # Check code signature entitlements
  CODE_SIG_APP_ID=$(codesign -d --entitlements :- "$HELPER_PATH" 2>/dev/null | plutil -p - 2>/dev/null | grep "application-identifier" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
  echo "  Code signature App ID: $CODE_SIG_APP_ID"
  
  # For TestFlight, the profile App ID must match the code signature App ID
  if [ "$HELPER_PROV_APP_ID" = "$CODE_SIG_APP_ID" ]; then
    echo "  ✅ Profile App ID matches code signature App ID"
    ((PASSED++))
  else
    echo "  ❌ FAIL: Profile App ID ($HELPER_PROV_APP_ID) does NOT match code signature App ID ($CODE_SIG_APP_ID)"
    echo "  This is why TestFlight validation fails - the profile doesn't match the signature"
    ((FAILED++))
  fi
  
  echo ""
done

echo "=== Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
  echo "✅ All helper apps properly configured"
  exit 0
else
  echo "❌ Some helper apps have mismatched provisioning profiles"
  exit 1
fi

