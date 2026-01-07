#!/bin/bash
set -euo pipefail

# Verify the MAS app and pkg meet all requirements

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Get app path
if [ -f ".mas-app-path" ]; then
  APP="$(cat .mas-app-path)"
else
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
fi

PKG="$REPO_ROOT/dist/mas/com.nexuscountdown.pkg"

PASSED=0
FAILED=0

function check() {
  local description="$1"
  local condition="$2"
  local details="${3:-}"
  
  if eval "$condition"; then
    echo "✅ PASS: $description${details:+ - $details}"
    ((PASSED++))
  else
    echo "❌ FAIL: $description${details:+ - $details}"
    ((FAILED++))
  fi
}

echo "🔍 Verifying MAS app and package..."
echo ""

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "❌ ERROR: App bundle not found"
  exit 1
fi

INFO_PLIST="$APP/Contents/Info.plist"

# APP CHECKS
echo "=== App Bundle Checks ==="

# Info.plist checks
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo "")
check "CFBundleIdentifier" "[ \"$BUNDLE_ID\" = \"com.nexuscountdown\" ]" "Found: $BUNDLE_ID"

CATEGORY=$(/usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" "$INFO_PLIST" 2>/dev/null || echo "")
check "LSApplicationCategoryType" "[ \"$CATEGORY\" = \"public.app-category.utilities\" ]" "Found: $CATEGORY"

# Entitlements check
ENTITLEMENTS_OUT=$(codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null || echo "")
check "Entitlements contain application-identifier" "echo \"$ENTITLEMENTS_OUT\" | grep -q 'T6YG6KXA9D.com.nexuscountdown'"
check "Entitlements contain team-identifier" "echo \"$ENTITLEMENTS_OUT\" | grep -q 'T6YG6KXA9D'"
check "Entitlements contain app-sandbox" "echo \"$ENTITLEMENTS_OUT\" | grep -q 'app-sandbox.*true'"

# Code signature
if codesign -vvv --deep --strict "$APP" 2>&1 | grep -q "satisfies its Designated Requirement"; then
  check "Code signature valid" "true"
else
  check "Code signature valid" "false" "Deep validation failed"
  codesign -vvv --deep --strict "$APP" 2>&1 | head -5 || true
fi

# Quarantine
QUARANTINE=$(xattr "$APP" -lr 2>/dev/null | grep -i quarantine || echo "")
check "No quarantine attributes" "[ -z \"$QUARANTINE\" ]" "Found quarantine attributes"

# Architecture
BINARY_PATH="$APP/Contents/MacOS/Nexus Countdown"
if [ -f "$BINARY_PATH" ]; then
  ARCH_OUT=$(file "$BINARY_PATH" 2>/dev/null || echo "")
  echo "ℹ  Architecture: $ARCH_OUT"
  check "Binary architecture" "echo \"$ARCH_OUT\" | grep -qE '(arm64|x86_64|universal)'"
fi

# Provisioning profile
PROV_PROFILE="$APP/Contents/embedded.provisionprofile"
check "Provisioning profile embedded" "[ -f \"$PROV_PROFILE\" ]"

# Helper app bundle IDs (must match main app for TestFlight)
MAIN_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
HELPER_COUNT=0
HELPER_MISMATCH=0
# Use nullglob to handle case where glob doesn't match
shopt -s nullglob 2>/dev/null || true
for helper in "$APP/Contents/Frameworks/"*Helper*.app; do
  if [ -d "$helper" ]; then
    HELPER_COUNT=$((HELPER_COUNT + 1))
    HELPER_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$helper/Contents/Info.plist" 2>/dev/null || echo "")
    if [ "$HELPER_BUNDLE_ID" != "$MAIN_BUNDLE_ID" ]; then
      HELPER_MISMATCH=$((HELPER_MISMATCH + 1))
      echo "   ⚠️  $(basename "$helper"): Bundle ID mismatch ($HELPER_BUNDLE_ID vs $MAIN_BUNDLE_ID)"
    fi
  fi
done
shopt -u nullglob 2>/dev/null || true
if [ $HELPER_COUNT -gt 0 ]; then
  if [ $HELPER_MISMATCH -eq 0 ]; then
    check "Helper app bundle IDs match main app" "true"
  else
    check "Helper app bundle IDs match main app" "false" "$HELPER_MISMATCH/$HELPER_COUNT helpers have mismatched bundle IDs"
  fi
fi

echo ""
echo "=== Package Checks ==="

if [ ! -f "$PKG" ]; then
  check "PKG file exists" "false" "Not found: $PKG"
else
  check "PKG file exists" "true"
  
  # PKG signature
  PKG_SIG=$(pkgutil --check-signature "$PKG" 2>&1 || echo "")
  if echo "$PKG_SIG" | grep -q "3rd Party Mac Developer Installer: Adam Parsons"; then
    check "PKG signed with MAS installer cert" "true"
  else
    check "PKG signed with MAS installer cert" "false"
    echo "$PKG_SIG" | head -10
  fi
  
  # PKG quarantine
  PKG_QUARANTINE=$(xattr "$PKG" -lr 2>/dev/null | grep -i quarantine || echo "")
  check "PKG has no quarantine attributes" "[ -z \"$PKG_QUARANTINE\" ]"
fi

echo ""
echo "=== Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
  echo ""
  echo "✅ MAS verification PASS"
  exit 0
else
  echo ""
  echo "❌ MAS verification FAIL ($FAILED check(s) failed)"
  exit 1
fi

