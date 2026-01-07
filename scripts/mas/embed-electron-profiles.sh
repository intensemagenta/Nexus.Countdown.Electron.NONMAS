#!/bin/bash
set -euo pipefail

# Embed provisioning profile into main app and all nested bundles that have application identifiers

APP="$1"
PROFILE="$2"

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "❌ ERROR: App bundle not found: $APP"
  exit 1
fi

if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
  echo "❌ ERROR: Provisioning profile not found: $PROFILE"
  exit 1
fi

echo "📦 Embedding provisioning profile into bundles..."
echo "   App: $(basename "$APP")"
echo "   Profile: $(basename "$PROFILE")"
echo ""

# Embed in main app
echo "   Main app..."
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Find all nested bundles that might need profiles
# Use both find and glob to catch all helper apps
EMBEDDED_COUNT=0

# First, try helper apps specifically (most common case)
for BUNDLE in "$APP/Contents/Frameworks/"*Helper*.app "$APP/Contents/Frameworks/"*.appex; do
  if [ -d "$BUNDLE" ] && [ -f "$BUNDLE/Contents/Info.plist" ]; then
    BUNDLE_NAME=$(basename "$BUNDLE")
    cp "$PROFILE" "$BUNDLE/Contents/embedded.provisionprofile"
    EMBEDDED_COUNT=$((EMBEDDED_COUNT + 1))
    
    # Check if already has app identifier
    if codesign -d --entitlements :- "$BUNDLE" 2>/dev/null | plutil -p - 2>/dev/null | grep -q "application-identifier"; then
      echo "     ✅ $BUNDLE_NAME (has app identifier)"
    else
      echo "     ✅ $BUNDLE_NAME (will have app identifier after signing)"
    fi
  fi
done

# Also search for any other .app/.appex bundles we might have missed
BUNDLES=$(find "$APP/Contents" -type d \( -name "*.app" -o -name "*.appex" \) ! -path "*/Frameworks/*Helper*.app" 2>/dev/null | sort || true)

if [ -n "$BUNDLES" ]; then
  for BUNDLE in $BUNDLES; do
    # Skip if we already processed this one
    if [ -f "$BUNDLE/Contents/embedded.provisionprofile" ]; then
      continue
    fi
    
    # Check if bundle has Info.plist
    if [ -f "$BUNDLE/Contents/Info.plist" ] || [ -f "$BUNDLE/Info.plist" ]; then
      BUNDLE_NAME=$(basename "$BUNDLE")
      
      if [ -d "$BUNDLE/Contents" ]; then
        cp "$PROFILE" "$BUNDLE/Contents/embedded.provisionprofile"
        EMBEDDED_COUNT=$((EMBEDDED_COUNT + 1))
        echo "     ✅ $BUNDLE_NAME"
      elif [ -f "$BUNDLE/Info.plist" ]; then
        BUNDLE_DIR=$(dirname "$BUNDLE")
        mkdir -p "$BUNDLE_DIR/Contents"
        cp "$PROFILE" "$BUNDLE_DIR/Contents/embedded.provisionprofile"
        EMBEDDED_COUNT=$((EMBEDDED_COUNT + 1))
        echo "     ✅ $BUNDLE_NAME"
      fi
    fi
  done
fi

# NOTE: Squirrel.framework and ShipIt should NOT be present in MAS builds
# They are removed by remove-squirrel-mas.sh script before signing
# If Squirrel exists here, it's an error (should have been removed)
SQUIRREL_FRAMEWORK="$APP/Contents/Frameworks/Squirrel.framework"
if [ -d "$SQUIRREL_FRAMEWORK" ]; then
  echo "     ⚠️  WARNING: Squirrel.framework found (should have been removed for MAS)"
  echo "     Skipping ShipIt profile embedding - Squirrel should be removed"
fi

echo ""
echo "✅ Embedded profile into main app + $EMBEDDED_COUNT nested bundle(s)"
