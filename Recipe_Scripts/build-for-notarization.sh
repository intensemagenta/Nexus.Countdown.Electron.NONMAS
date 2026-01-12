#!/bin/bash
set -euo pipefail

# Build and sign a DMG for Mac distribution outside the App Store
# Ready for notarization upload to Apple's portal

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "📦 Building signed DMG for notarization (Developer ID)..."

cd apps/electron

# Ensure icon exists
ICON_SOURCE="$REPO_ROOT/icons/Icons/countdown.icns"
ICON_DEST="build/icons/icon.icns"
if [ ! -f "$ICON_DEST" ] && [ -f "$ICON_SOURCE" ]; then
  echo "Copying icon..."
  mkdir -p "$(dirname "$ICON_DEST")"
  cp "$ICON_SOURCE" "$ICON_DEST"
fi

# Find npm and npx (try common locations)
NPM_CMD="npm"
NPX_CMD="npx"
if ! command -v npm >/dev/null 2>&1; then
  if [ -f "/opt/homebrew/bin/npm" ]; then
    NPM_CMD="/opt/homebrew/bin/npm"
    NPX_CMD="/opt/homebrew/bin/npx"
  elif [ -f "/usr/local/bin/npm" ]; then
    NPM_CMD="/usr/local/bin/npm"
    NPX_CMD="/usr/local/bin/npx"
  else
    echo "❌ ERROR: npm not found. Please install Node.js or add npm to PATH"
    exit 1
  fi
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  $NPM_CMD install
fi

# Find Developer ID signing identity
FULL_IDENTITY="Developer ID Application: Adam Parsons (T6YG6KXA9D)"
IDENTITY="Adam Parsons (T6YG6KXA9D)"  # electron-builder wants just the name

if ! security find-identity -v -p codesigning | grep -q "$FULL_IDENTITY"; then
  echo "❌ ERROR: Developer ID certificate not found or missing private key"
  echo "Looking for: $FULL_IDENTITY"
  echo ""
  echo "Available certificates:"
  security find-identity -v -p codesigning | grep -i "application" || echo "  (none found)"
  echo ""
  echo "If the certificate exists but isn't showing, you may need to:"
  echo "1. Export the certificate with private key from Keychain Access as .p12"
  echo "2. Import it: security import certificate.p12 -k ~/Library/Keychains/login.keychain-db"
  echo "3. Or download it from: https://developer.apple.com/account/resources/certificates/list"
  exit 1
fi

echo "✅ Found Developer ID certificate: $FULL_IDENTITY"

# Create output directory
OUTPUT_DIR="dist/non_mas"
mkdir -p "$OUTPUT_DIR"

# Build DMG using electron-builder with Developer ID configuration
echo ""
echo "Building DMG with electron-builder (Developer ID)..."

# Enable electron-builder's automatic signing with Developer ID
# This handles resource forks better than manual signing
export CSC_IDENTITY_AUTO_DISCOVERY=true
export CSC_NAME="$IDENTITY"
export CSC_LINK=""
export CSC_KEY_PASSWORD=""
export APPLE_ID=""
export APPLE_ID_PASS=""
# Tell electron-builder to sign everything
export CSC_PROVIDER=""

# Clean extended attributes that can prevent code signing
# Skip node_modules and other large directories to avoid hanging
echo "Cleaning extended attributes from source (skipping node_modules)..."
find . -type f -not -path "./node_modules/*" -not -path "./dist/*" -not -path "./.git/*" -exec xattr -c {} \; 2>/dev/null || true

# Build without signing (electron-builder will package but not sign)
# Temporarily rename afterPack to disable it for non-MAS builds
if [ -f "package.json" ]; then
  # Create a temp package.json without afterPack
  cp package.json package.json.backup
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    delete pkg.build.afterPack;
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
  "
fi

# Try to build - if signing fails, we'll handle it manually
set +e  # Don't exit on error
echo "Running electron-builder..."
echo "Note: Rebuilding native dependencies may take 5-10 minutes on first run..."
echo ""

# Run electron-builder (native rebuild is necessary for proper signing)
$NPX_CMD electron-builder --mac dir \
  --config.directories.output="$OUTPUT_DIR" \
  --config.mac.target=dir \
  --config.mac.hardenedRuntime=true \
  --config.mac.gatekeeperAssess=true \
  --config.mac.entitlements="build/entitlements.dev-id.plist" \
  --config.mac.entitlementsInherit="build/entitlements.dev-id.inherit.plist" \
  --config.mac.category="public.app-category.utilities" \
  --config.mac.minimumSystemVersion="12.0" \
  --config.mac.icon="build/icons/icon.icns" \
  --config.mac.identity="$IDENTITY" \
  --config.mac.signIgnore="node_modules" \
  --publish=never 2>&1

BUILD_EXIT_CODE=$?
set -e  # Re-enable exit on error

# Restore package.json
if [ -f "package.json.backup" ]; then
  mv package.json.backup package.json
fi

# Check if app bundle was created despite signing error
if [ ! -d "$OUTPUT_DIR/mac-arm64/Nexus Countdown.app" ] && [ ! -d "$OUTPUT_DIR/mac/Nexus Countdown.app" ] && [ ! -d "$OUTPUT_DIR/mac-x64/Nexus Countdown.app" ]; then
  if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: Build failed and app bundle not found"
    exit 1
  fi
fi

# Find the built app bundle
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

if [ -z "$APP_PATH" ]; then
  echo "❌ ERROR: Could not find built app bundle in $OUTPUT_DIR"
  echo "Searched patterns: ${APP_PATTERNS[*]}"
  exit 1
fi

echo ""
echo "✅ App bundle created: $APP_PATH"

# Clean extended attributes from built app before signing
echo ""
echo "Cleaning extended attributes from built app..."
# Remove all extended attributes and resource forks recursively from entire app bundle
xattr -cr "$APP_PATH" 2>/dev/null || true
# Remove .DS_Store and other Finder metadata
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true

# Aggressively remove ALL extended attributes from entire app bundle
echo "  Removing all extended attributes from app bundle..."
# Remove all xattrs recursively first
xattr -cr "$APP_PATH" 2>/dev/null || true

# Remove specific problematic attributes that prevent signing
echo "  Removing Finder information and other problematic attributes..."
find "$APP_PATH" -type f -o -type d | while read -r item; do
  # Remove all known problematic attributes
  xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$item" 2>/dev/null || true
  xattr -d com.apple.quarantine "$item" 2>/dev/null || true
  xattr -d com.apple.fileprovider.fpfs#P "$item" 2>/dev/null || true
  xattr -d com.apple.provenance "$item" 2>/dev/null || true
  # Remove all other xattrs except code signature
  for attr in $(xattr -l "$item" 2>/dev/null | cut -d: -f1); do
    if [ "$attr" != "com.apple.cs.CodeDirectory" ] && [ "$attr" != "com.apple.cs.CodeRequirements" ] && [ "$attr" != "com.apple.cs.CodeSignature" ]; then
      xattr -d "$attr" "$item" 2>/dev/null || true
    fi
  done
done

# Remove .DS_Store and ._ files
find "$APP_PATH" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP_PATH" -name "._*" -delete 2>/dev/null || true

# Use SetFile to remove Finder information if available
if command -v SetFile >/dev/null 2>&1; then
  echo "  Clearing Finder information with SetFile..."
  find "$APP_PATH" -type f -exec SetFile -c "" -t "" {} \; 2>/dev/null || true
fi

# Final cleanup pass - remove ALL xattrs
xattr -cr "$APP_PATH" 2>/dev/null || true
echo "  ✅ Extended attributes removed"

# Sign the app bundle manually
echo ""
echo "🔐 Signing app bundle with: $FULL_IDENTITY"
echo "This may take a minute..."

# Sign all libraries and binaries in Electron Framework first
echo "  Signing Electron Framework components..."
ELECTRON_FRAMEWORK="$APP_PATH/Contents/Frameworks/Electron Framework.framework"
if [ -d "$ELECTRON_FRAMEWORK" ]; then
  # Sign all .dylib files
  find "$ELECTRON_FRAMEWORK" -name "*.dylib" -type f | while read -r dylib; do
    echo "    Signing: $(basename "$dylib")"
    codesign --sign "$FULL_IDENTITY" \
      --force \
      --timestamp \
      --options runtime \
      "$dylib" 2>&1 | grep -v "replacing existing signature" || true
  done
  
  # Sign chrome_crashpad_handler
  CRASHPAD_HANDLER="$ELECTRON_FRAMEWORK/Versions/A/Helpers/chrome_crashpad_handler"
  if [ -f "$CRASHPAD_HANDLER" ]; then
    echo "    Signing: chrome_crashpad_handler"
    codesign --sign "$FULL_IDENTITY" \
      --force \
      --timestamp \
      --options runtime \
      --entitlements "build/entitlements.dev-id.inherit.plist" \
      "$CRASHPAD_HANDLER" 2>&1 | grep -v "replacing existing signature" || true
  fi
  
  # Sign Electron Framework binary
  FRAMEWORK_BINARY="$ELECTRON_FRAMEWORK/Versions/A/Electron Framework"
  if [ -f "$FRAMEWORK_BINARY" ]; then
    echo "    Signing: Electron Framework"
    codesign --sign "$FULL_IDENTITY" \
      --force \
      --timestamp \
      --options runtime \
      "$FRAMEWORK_BINARY" 2>&1 | grep -v "replacing existing signature" || true
  fi
fi

# Sign all helper apps (remove signatures first, then clean, then sign)
HELPER_APPS=$(find "$APP_PATH/Contents/Frameworks" -name "*.app" -type d 2>/dev/null || true)
if [ -n "$HELPER_APPS" ]; then
  while IFS= read -r helper; do
    echo "  Signing helper: $(basename "$helper")"
    # Remove any existing signature
    codesign --remove-signature "$helper" 2>/dev/null || true
    # Clean extended attributes from this helper app
    xattr -cr "$helper" 2>/dev/null || true
    find "$helper" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
    find "$helper" -exec xattr -d com.apple.fileprovider.fpfs#P {} \; 2>/dev/null || true
    find "$helper" -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
    # Now sign
    codesign --sign "$FULL_IDENTITY" \
      --force \
      --timestamp \
      --options runtime \
      --entitlements "build/entitlements.dev-id.inherit.plist" \
      "$helper" 2>&1 | grep -vE "(replacing existing signature|resource fork|Finder information)" || true
    # Verify the signature was actually created
    if codesign -vv "$helper" 2>&1 | grep -q "valid on disk"; then
      echo "    ✅ Helper app signed successfully"
    else
      echo "    ⚠️  Warning: Helper app signature verification failed"
    fi
  done <<< "$HELPER_APPS"
fi

# Sign framework binaries (Squirrel, Mantle, ReactiveObjC)
# IMPORTANT: Sign resources (like ShipIt) BEFORE signing the framework binary
FRAMEWORKS=$(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null || true)
if [ -n "$FRAMEWORKS" ]; then
  while IFS= read -r framework; do
    FRAMEWORK_NAME=$(basename "$framework" .framework)
    
    # Sign ShipIt FIRST if it exists in Squirrel (before signing the framework binary)
    SHIPIT="$framework/Versions/A/Resources/ShipIt"
    if [ -f "$SHIPIT" ]; then
      echo "  Signing ShipIt (before framework): $(basename "$framework")"
      codesign --remove-signature "$SHIPIT" 2>/dev/null || true
      codesign --sign "$FULL_IDENTITY" \
        --force \
        --timestamp \
        --options runtime \
        --entitlements "build/entitlements.dev-id.inherit.plist" \
        "$SHIPIT" 2>&1 | grep -v "replacing existing signature" || true
    fi
    
    # Now sign the framework binary
    FRAMEWORK_BINARY=$(find "$framework" -name "$FRAMEWORK_NAME" -type f | head -1)
    if [ -f "$FRAMEWORK_BINARY" ]; then
      echo "  Signing framework: $FRAMEWORK_NAME"
      codesign --remove-signature "$FRAMEWORK_BINARY" 2>/dev/null || true
      codesign --sign "$FULL_IDENTITY" \
        --force \
        --timestamp \
        --options runtime \
        "$FRAMEWORK_BINARY" 2>&1 | grep -v "replacing existing signature" || true
    fi
  done <<< "$FRAMEWORKS"
fi

# Sign the main app bundle
echo "  Signing main app bundle..."
# Remove any existing signatures first to avoid conflicts
codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# Copy app bundle to clean location without extended attributes
echo "  Copying app bundle to remove all extended attributes..."
TEMP_DIR=$(mktemp -d)
CLEAN_APP="$TEMP_DIR/$(basename "$APP_PATH")"
# Use cp -R -X to copy without extended attributes
cp -R -X "$APP_PATH" "$CLEAN_APP" 2>/dev/null
# Remove any remaining xattrs
xattr -cr "$CLEAN_APP" 2>/dev/null || true
# Replace original with clean copy
rm -rf "$APP_PATH"
mv "$CLEAN_APP" "$APP_PATH"
rm -rf "$TEMP_DIR"
echo "  ✅ App bundle cleaned"

# Sign the app bundle
echo "  Signing app bundle..."
SIGN_OUTPUT=$(codesign --sign "$FULL_IDENTITY" \
  --force \
  --timestamp \
  --options runtime \
  --entitlements "build/entitlements.dev-id.plist" \
  "$APP_PATH" 2>&1)

# Filter out resource fork warnings but show other errors
echo "$SIGN_OUTPUT" | grep -vE "(resource fork|Finder information)" || true

# Check if signature was actually created
VERIFY_OUTPUT=$(codesign -vv "$APP_PATH" 2>&1)
if echo "$VERIFY_OUTPUT" | grep -q "valid on disk"; then
  echo "  ✅ App bundle signed successfully"
  echo "$VERIFY_OUTPUT" | grep "valid on disk" || true
else
  echo "  ❌ ERROR: Failed to sign app bundle"
  echo "$VERIFY_OUTPUT" | head -10
  exit 1
fi

# Verify app bundle signature
echo ""
echo "Verifying app bundle signature..."
if codesign -vvv --deep --strict "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
  echo "✅ App bundle signature is valid"
else
  echo "⚠️  Warning: App bundle signature verification issue"
  codesign -vvv --deep --strict "$APP_PATH" || true
fi

# Create DMG using electron-builder
echo ""
echo "Creating DMG..."
$NPX_CMD electron-builder --mac dmg \
  --config.directories.output="$OUTPUT_DIR" \
  --config.mac.target=dmg \
  --prepackaged="$APP_PATH" \
  --config.dmg.sign=false

# Find the DMG
DMG_PATTERNS=(
  "$OUTPUT_DIR/Nexus Countdown*.dmg"
  "$OUTPUT_DIR/mac/*.dmg"
  "$OUTPUT_DIR/*.dmg"
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

if [ -z "$DMG_PATH" ]; then
  echo "❌ ERROR: Could not find built DMG in $OUTPUT_DIR"
  echo "Searched patterns: ${DMG_PATTERNS[*]}"
  exit 1
fi

echo ""
echo "✅ DMG created: $DMG_PATH"

# Check hardened runtime
echo ""
echo "Checking hardened runtime..."
if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "com.apple.security.cs.allow-jit"; then
  echo "✅ Hardened runtime entitlements found"
else
  echo "⚠️  Warning: Hardened runtime entitlements not found"
fi

# Sign the DMG
echo ""
echo "🔐 Signing DMG with: $FULL_IDENTITY"
codesign --sign "$FULL_IDENTITY" --options runtime "$DMG_PATH"

if [ $? -ne 0 ]; then
  echo "❌ ERROR: Failed to sign DMG"
  exit 1
fi

# Verify DMG signature
echo ""
echo "Verifying DMG signature..."
DMG_VERIFY=$(codesign -vvv "$DMG_PATH" 2>&1)
if echo "$DMG_VERIFY" | grep -q "valid on disk"; then
  echo "✅ DMG signature is valid"
  if echo "$DMG_VERIFY" | grep -q "satisfies its Designated Requirement"; then
    echo "✅ DMG satisfies Designated Requirement"
  fi
else
  echo "⚠️  Warning: DMG signature verification issue"
  echo "$DMG_VERIFY"
fi

# Create zip file for notarization upload (Apple requires zip format for app bundles)
ZIP_PATH="$OUTPUT_DIR/Nexus Countdown-for-notarization.zip"
echo ""
echo "Creating zip file for notarization upload..."
cd "$(dirname "$APP_PATH")"
ditto -c -k --keepParent "$(basename "$APP_PATH")" "$ZIP_PATH"

if [ -f "$ZIP_PATH" ]; then
  echo "✅ Zip file created: $ZIP_PATH"
else
  echo "❌ ERROR: Failed to create zip file"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build complete! Files ready for notarization:"
echo ""
echo "📦 Signed App Bundle:"
echo "   $APP_PATH"
echo ""
echo "💿 Signed DMG (ready for testing and notarization):"
echo "   $DMG_PATH"
echo ""
echo "📎 Zip file for Apple portal upload:"
echo "   $ZIP_PATH"
echo ""
echo "Next steps:"
echo "1. Test the DMG locally: open $DMG_PATH"
echo "2. Upload $ZIP_PATH to Apple's notarization portal"
echo "3. After approval, staple the ticket:"
echo "   xcrun stapler staple \"$APP_PATH\""
echo "   xcrun stapler staple \"$DMG_PATH\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
