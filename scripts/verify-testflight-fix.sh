#!/bin/bash
set -euo pipefail

# Verify that the TestFlight fix is in place (helper bundle IDs match main app)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_PATH="$REPO_ROOT/dist/mas/com.nexuscountdown.pkg"

if [ ! -f "$PKG_PATH" ]; then
  echo "❌ PKG not found: $PKG_PATH"
  exit 1
fi

echo "🔍 Verifying TestFlight fix (helper bundle IDs)..."
echo ""

EXPAND_DIR="/tmp/verify_testflight_fix_$$"
trap "rm -rf '$EXPAND_DIR'" EXIT

pkgutil --expand "$PKG_PATH" "$EXPAND_DIR" >/dev/null 2>&1
cd "$EXPAND_DIR/com.nexuscountdown.pkg"
cat Payload | gunzip | cpio -i -d >/dev/null 2>&1

APP="Nexus Countdown.app"
MAIN_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null)

echo "Main app bundle ID: $MAIN_BUNDLE_ID"
echo ""

ALL_MATCH=true
HELPER_COUNT=0

for helper in "$APP/Contents/Frameworks/"*Helper*.app; do
  if [ -d "$helper" ]; then
    HELPER_COUNT=$((HELPER_COUNT + 1))
    HELPER_NAME=$(basename "$helper")
    HELPER_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$helper/Contents/Info.plist" 2>/dev/null)
    
    if [ "$HELPER_BUNDLE_ID" = "$MAIN_BUNDLE_ID" ]; then
      echo "✅ $HELPER_NAME: $HELPER_BUNDLE_ID (matches)"
    else
      echo "❌ $HELPER_NAME: $HELPER_BUNDLE_ID (MISMATCH - should be $MAIN_BUNDLE_ID)"
      ALL_MATCH=false
    fi
  fi
done

echo ""
if [ "$ALL_MATCH" = true ] && [ $HELPER_COUNT -gt 0 ]; then
  echo "✅ All $HELPER_COUNT helper apps have matching bundle IDs"
  echo "✅ This should resolve TestFlight validation error 90885"
  exit 0
else
  echo "❌ Some helper apps have mismatched bundle IDs"
  exit 1
fi

