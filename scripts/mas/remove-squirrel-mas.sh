#!/bin/bash
set -euo pipefail

# Remove Squirrel.framework and ShipIt from MAS app bundle
# This is required because:
# - ShipIt needs a provisioning profile for MAS/TestFlight
# - We don't use auto-updater (MAS handles updates)
# - Removing Squirrel eliminates the 90885 error

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Get app path from previous build step
if [ -f ".mas-app-path" ]; then
  APP="$(cat .mas-app-path)"
else
  echo "❌ ERROR: Could not find app bundle. Run build script first."
  exit 1
fi

if [ ! -d "$APP" ]; then
  echo "❌ ERROR: App bundle not found at: $APP"
  exit 1
fi

echo "🗑️  Removing Squirrel.framework from MAS app..."
echo "   App: $APP"

SQUIRREL_FRAMEWORK="$APP/Contents/Frameworks/Squirrel.framework"
REMOVED=false

# Check if Squirrel.framework exists
if [ -d "$SQUIRREL_FRAMEWORK" ]; then
  echo "   Found Squirrel.framework, removing..."
  rm -rf "$SQUIRREL_FRAMEWORK"
  REMOVED=true
  echo "   ✅ Removed Squirrel.framework"
else
  echo "   ℹ️  Squirrel.framework not found (already removed or never present)"
fi

# Double-check: verify ShipIt is gone
SHIPIT_PATH=$(find "$APP/Contents" -maxdepth 10 -iname "ShipIt" -type f 2>/dev/null | head -1 || true)
if [ -n "$SHIPIT_PATH" ]; then
  echo "   ⚠️  WARNING: Found ShipIt at: $SHIPIT_PATH"
  echo "   Removing ShipIt..."
  rm -f "$SHIPIT_PATH"
  REMOVED=true
  echo "   ✅ Removed ShipIt"
fi

# Verify no Squirrel.framework remains
if [ -d "$SQUIRREL_FRAMEWORK" ]; then
  echo "   ❌ ERROR: Squirrel.framework still exists after removal attempt"
  exit 1
fi

# Verify no ShipIt remains
REMAINING_SHIPIT=$(find "$APP/Contents" -maxdepth 10 -iname "ShipIt" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING_SHIPIT" != "0" ]; then
  echo "   ❌ ERROR: ShipIt still exists after removal attempt"
  find "$APP/Contents" -maxdepth 10 -iname "ShipIt" -type f
  exit 1
fi

if [ "$REMOVED" = true ]; then
  echo ""
  echo "✅ Squirrel.framework and ShipIt removed successfully"
  echo "   The app bundle will need to be re-signed after this removal"
else
  echo ""
  echo "✅ No Squirrel components found (nothing to remove)"
fi


