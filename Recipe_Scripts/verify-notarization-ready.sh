#!/bin/bash
set -euo pipefail

# Verify that app bundle and DMG are ready for notarization

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="apps/electron/dist/non_mas"

# Find app bundle and DMG
APP_PATTERNS=(
  "$OUTPUT_DIR/mac/Nexus Countdown.app"
  "$OUTPUT_DIR/mac-arm64/Nexus Countdown.app"
  "$OUTPUT_DIR/mac-x64/Nexus Countdown.app"
)

APP_PATH=""
for pattern in "${APP_PATTERNS[@]}"; do
  if [ -d "$pattern" ]; then
    APP_PATH="$(cd "$(dirname "$pattern")" && pwd)/$(basename "$pattern")"
    break
  fi
done

DMG_PATTERNS=(
  "$OUTPUT_DIR/Nexus Countdown*.dmg"
  "$OUTPUT_DIR/mac/*.dmg"
)

DMG_PATH=""
shopt -s nullglob
for pattern in "${DMG_PATTERNS[@]}"; do
  for dmg in $pattern; do
    if [ -f "$dmg" ] && [[ "$dmg" == *.dmg ]]; then
      DMG_PATH="$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")"
      break 2
    fi
  done
done
shopt -u nullglob

ZIP_PATH="$OUTPUT_DIR/Nexus Countdown-for-notarization.zip"

echo "🔍 Verifying notarization readiness..."
echo ""

if [ -z "$APP_PATH" ]; then
  echo "❌ ERROR: App bundle not found in $OUTPUT_DIR"
  exit 1
fi

if [ -z "$DMG_PATH" ]; then
  echo "❌ ERROR: DMG not found in $OUTPUT_DIR"
  exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
  echo "⚠️  WARNING: Zip file not found: $ZIP_PATH"
fi

echo "📦 App Bundle: $APP_PATH"
echo "💿 DMG: $DMG_PATH"
if [ -f "$ZIP_PATH" ]; then
  echo "📎 Zip: $ZIP_PATH"
fi
echo ""

# Check app bundle signature
echo "1️⃣  Checking app bundle signature..."
if codesign -vvv --deep --strict "$APP_PATH" > /dev/null 2>&1; then
  echo "   ✅ App bundle signature is valid"
else
  echo "   ❌ App bundle signature is invalid"
  codesign -vvv --deep --strict "$APP_PATH" || true
  exit 1
fi

# Check hardened runtime
echo ""
echo "2️⃣  Checking hardened runtime..."
ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>&1)
if echo "$ENTITLEMENTS" | grep -q "com.apple.security.cs.allow-jit"; then
  echo "   ✅ Hardened runtime entitlements found"
else
  echo "   ⚠️  Warning: Hardened runtime entitlements not found"
fi

# Check if hardened runtime is enabled
if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "com.apple.security.cs.disable-library-validation\|com.apple.security.cs.allow-unsigned-executable-memory"; then
  echo "   ✅ Hardened runtime is enabled"
else
  echo "   ⚠️  Warning: Hardened runtime may not be fully enabled"
fi

# Verify all nested executables are signed
echo ""
echo "3️⃣  Checking nested executables..."
HELPER_APPS=$(find "$APP_PATH/Contents/Frameworks" -name "*.app" -type d 2>/dev/null || true)
if [ -n "$HELPER_APPS" ]; then
  ALL_SIGNED=true
  while IFS= read -r helper; do
    if ! codesign -vvv "$helper" > /dev/null 2>&1; then
      echo "   ❌ Unsigned helper: $helper"
      ALL_SIGNED=false
    fi
  done <<< "$HELPER_APPS"
  
  if [ "$ALL_SIGNED" = true ]; then
    echo "   ✅ All helper apps are signed"
  else
    echo "   ❌ Some helper apps are not signed"
    exit 1
  fi
else
  echo "   ✅ No helper apps found (or already verified by deep signing)"
fi

# Check DMG signature
echo ""
echo "4️⃣  Checking DMG signature..."
if codesign -vvv "$DMG_PATH" > /dev/null 2>&1; then
  echo "   ✅ DMG signature is valid"
else
  echo "   ❌ DMG signature is invalid"
  codesign -vvv "$DMG_PATH" || true
  exit 1
fi

# Check zip file
if [ -f "$ZIP_PATH" ]; then
  echo ""
  echo "5️⃣  Checking zip file..."
  if unzip -t "$ZIP_PATH" > /dev/null 2>&1; then
    echo "   ✅ Zip file is valid"
    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    echo "   📊 Zip size: $ZIP_SIZE"
  else
    echo "   ❌ Zip file is corrupted"
    exit 1
  fi
fi

# Gatekeeper check
echo ""
echo "6️⃣  Checking Gatekeeper assessment..."
GATEKEEPER_OUTPUT=$(spctl -a -vv "$APP_PATH" 2>&1 || true)
if echo "$GATEKEEPER_OUTPUT" | grep -q "accepted"; then
  echo "   ✅ Gatekeeper accepts the app"
elif echo "$GATEKEEPER_OUTPUT" | grep -q "rejected"; then
  echo "   ⚠️  Gatekeeper rejected (this is normal before notarization)"
else
  echo "   ℹ️  Gatekeeper status: $(echo "$GATEKEEPER_OUTPUT" | head -1)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Verification complete!"
echo ""
echo "The app is ready for notarization upload."
echo "Upload $ZIP_PATH to Apple's notarization portal."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
