#!/bin/bash
set -euo pipefail

# Build and sign a DMG for Mac distribution
# Always signs the DMG using available certificates

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "📦 Building signed DMG for Mac distribution..."

cd apps/electron

# Ensure icon exists
ICON_SOURCE="$REPO_ROOT/icons/Icons/countdown.icns"
ICON_DEST="build/icons/icon.icns"
if [ ! -f "$ICON_DEST" ] && [ -f "$ICON_SOURCE" ]; then
  echo "Copying icon..."
  mkdir -p "$(dirname "$ICON_DEST")"
  cp "$ICON_SOURCE" "$ICON_DEST"
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

# Find signing identity - prefer Developer ID, fall back to MAS certificate
IDENTITY=""
DEVELOPER_ID="Developer ID Application: Adam Parsons (T6YG6KXA9D)"
MAS_ID="3rd Party Mac Developer Application: Adam Parsons (T6YG6KXA9D)"

if security find-identity -v -p codesigning | grep -q "$DEVELOPER_ID"; then
  IDENTITY="$DEVELOPER_ID"
  echo "✅ Found Developer ID certificate: $IDENTITY"
elif security find-identity -v -p codesigning | grep -q "$MAS_ID"; then
  IDENTITY="$MAS_ID"
  echo "✅ Found MAS certificate (using for signing): $IDENTITY"
  echo "⚠️  Note: MAS certificates are typically for App Store distribution"
else
  echo "❌ ERROR: No signing certificate found"
  echo "Looking for:"
  echo "  - $DEVELOPER_ID"
  echo "  - $MAS_ID"
  echo ""
  echo "Available certificates:"
  security find-identity -v -p codesigning | grep -i "application" || echo "  (none found)"
  exit 1
fi

# Build DMG using electron-builder
echo ""
echo "Building DMG with electron-builder..."

# Use electron-builder to create DMG
# Configure for Developer ID signing (not MAS)
npx electron-builder --mac dmg \
  --config.mac.entitlements=build/entitlements.dev-id.plist \
  --config.mac.entitlementsInherit=build/entitlements.dev-id.inherit.plist \
  --config.mac.hardenedRuntime=true \
  --config.mac.category=public.app-category.utilities \
  --config.mac.minimumSystemVersion=12.0 \
  --config.mac.icon=build/icons/icon.icns \
  --config.mac.identity="$IDENTITY" \
  --config.dmg.sign=false

# Find the built DMG
DMG_PATTERNS=(
  "dist/Nexus Countdown*.dmg"
  "dist/mac/*.dmg"
  "dist/mac-arm64/*.dmg"
  "dist/mac-x64/*.dmg"
  "dist/*.dmg"
)

DMG_PATH=""
for pattern in "${DMG_PATTERNS[@]}"; do
  for dmg in $pattern 2>/dev/null; do
    if [ -f "$dmg" ] && [[ "$dmg" == *.dmg ]]; then
      DMG_PATH="$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")"
      break 2
    fi
  done
done

if [ -z "$DMG_PATH" ]; then
  echo "❌ ERROR: Could not find built DMG in dist/"
  echo "Searched patterns: ${DMG_PATTERNS[*]}"
  exit 1
fi

echo ""
echo "✅ DMG created: $DMG_PATH"

# Remove quarantine attributes
xattr -cr "$DMG_PATH" || true

# Sign the DMG
echo ""
echo "🔐 Signing DMG with: $IDENTITY"
codesign --sign "$IDENTITY" --options runtime "$DMG_PATH"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: Failed to sign DMG"
  exit 1
fi

# Verify DMG signature
echo ""
echo "Verifying DMG signature..."
if codesign -vvv "$DMG_PATH" 2>&1 | grep -q "valid on disk"; then
  echo "✅ DMG signature is valid"
else
  echo "⚠️  Warning: DMG signature verification issue"
  codesign -vvv "$DMG_PATH" || true
  exit 1
fi

echo ""
echo "✅ Signed DMG ready: $DMG_PATH"
