#!/bin/bash
set -euo pipefail

# Build a signed .pkg installer for MAS

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Get app path - try to use paths-electron.js first
APP=""
if command -v node >/dev/null 2>&1; then
  APP=$(node "$REPO_ROOT/scripts/mas/paths-electron.js" 2>/dev/null || echo "")
fi

# Fallback to .mas-app-path or manual search
if [ -z "$APP" ] && [ -f "$REPO_ROOT/.mas-app-path" ]; then
  APP="$(cat "$REPO_ROOT/.mas-app-path")"
elif [ -z "$APP" ]; then
  APP_DIRS=(
    "apps/electron/dist/mac/Nexus Countdown.app"
    "apps/electron/dist/mac-unpacked/Nexus Countdown.app"
    "apps/electron/dist/mac-arm64-unpacked/Nexus Countdown.app"
    "apps/electron/dist/mac-x64-unpacked/Nexus Countdown.app"
    "apps/electron/dist/mac-universal/Nexus Countdown.app"
  )
  
  for candidate in "${APP_DIRS[@]}"; do
    CANDIDATE_PATH="$REPO_ROOT/$candidate"
    if [ -d "$CANDIDATE_PATH" ]; then
      APP="$(cd "$(dirname "$CANDIDATE_PATH")" && pwd)/$(basename "$CANDIDATE_PATH")"
      break
    fi
  done
fi

if [ -z "$APP" ]; then
  echo "❌ ERROR: Could not find signed app bundle. Run build and sign scripts first."
  exit 1
fi

if [ ! -d "$APP" ]; then
  echo "❌ ERROR: App bundle not found at: $APP"
  exit 1
fi

OUTPUT_DIR="$REPO_ROOT/dist/mas"
mkdir -p "$OUTPUT_DIR"

PKG_PATH="$OUTPUT_DIR/com.nexuscountdown.pkg"
INFO_PLIST="$APP/Contents/Info.plist"

if [ ! -f "$INFO_PLIST" ]; then
  echo "❌ ERROR: Info.plist not found at: $INFO_PLIST"
  exit 1
fi

INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Adam Parsons (T6YG6KXA9D)"

echo "📦 Building signed .pkg installer..."
echo "App: $APP"
echo "Output: $PKG_PATH"

# Remove existing pkg if present
if [ -f "$PKG_PATH" ]; then
  rm "$PKG_PATH"
fi

# Build signed pkg
productbuild \
  --component "$APP" "/Applications" \
  --sign "$INSTALLER_IDENTITY" \
  --product "$INFO_PLIST" \
  "$PKG_PATH"

if [ ! -f "$PKG_PATH" ]; then
  echo "❌ ERROR: Failed to create pkg"
  exit 1
fi

# Remove quarantine flags
echo "Removing quarantine attributes from pkg..."
xattr -cr "$PKG_PATH" || true

echo ""
echo "✅ Package created successfully: $PKG_PATH"

# Verify pkg signature
echo ""
echo "Verifying pkg signature..."
pkgutil --check-signature "$PKG_PATH" || {
  echo "⚠️  Warning: pkg signature verification had issues"
}

