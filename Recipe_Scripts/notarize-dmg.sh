#!/bin/bash
set -euo pipefail

# Submit DMG for Apple notarization using xcrun notarytool
# Usage: ./scripts/notarize-dmg.sh [--status] [--staple] [--wait]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="apps/electron/dist/non_mas"
TEAM_ID="T6YG6KXA9D"

# Find DMG
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

if [ -z "$DMG_PATH" ]; then
  echo "❌ ERROR: DMG not found in $OUTPUT_DIR"
  exit 1
fi

echo "📦 Found DMG: $DMG_PATH"
echo ""

# Check if DMG is signed
if ! codesign -vvv "$DMG_PATH" > /dev/null 2>&1; then
  echo "❌ ERROR: DMG is not signed. Please run 'npm run build:for-notarization' first."
  exit 1
fi

echo "✅ DMG is signed"
echo ""

# Check for required credentials
if [ -z "${APPLE_ID:-}" ]; then
  echo "Please enter your Apple ID email:"
  read -r APPLE_ID
fi

if [ -z "${APPLE_PASSWORD:-}" ]; then
  echo "Please enter your app-specific password (or @keychain:AC_PASSWORD for keychain):"
  read -rs APPLE_PASSWORD
  echo ""
fi

# Parse command line arguments
ACTION="submit"
if [[ "${1:-}" == "--status" ]]; then
  ACTION="status"
elif [[ "${1:-}" == "--staple" ]]; then
  ACTION="staple"
elif [[ "${1:-}" == "--wait" ]]; then
  ACTION="wait"
fi

case "$ACTION" in
  submit)
    echo "🚀 Submitting DMG for notarization..."
    echo ""
    
    SUBMISSION_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$TEAM_ID" \
      --wait 2>&1)
    
    echo "$SUBMISSION_OUTPUT"
    
    if echo "$SUBMISSION_OUTPUT" | grep -q "status: Accepted"; then
      echo ""
      echo "✅ Notarization successful!"
      echo ""
      echo "📌 Next step: Staple the notarization ticket:"
      echo "   npm run notarize:staple"
    elif echo "$SUBMISSION_OUTPUT" | grep -q "status: Invalid\|status: Rejected"; then
      echo ""
      echo "❌ Notarization failed!"
      exit 1
    fi
    ;;
    
  status)
    echo "📊 Checking notarization status..."
    xcrun notarytool history \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$TEAM_ID"
    ;;
    
  staple)
    echo "📎 Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    
    if [ $? -eq 0 ]; then
      echo "✅ Stapling successful!"
      echo ""
      echo "Verifying stapling..."
      if xcrun stapler validate "$DMG_PATH" > /dev/null 2>&1; then
        echo "✅ DMG is properly stapled and ready for distribution!"
      else
        echo "⚠️  Warning: Stapling verification failed"
      fi
    else
      echo "❌ Stapling failed. Make sure notarization was successful first."
      exit 1
    fi
    ;;
    
  wait)
    echo "⏳ Waiting for notarization to complete..."
    echo ""
    
    # Get the most recent submission
    SUBMISSION_ID=$(xcrun notarytool history \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$TEAM_ID" \
      2>&1 | grep -E '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1 | awk '{print $1}')
    
    if [ -z "$SUBMISSION_ID" ]; then
      echo "❌ No recent submission found"
      exit 1
    fi
    
    echo "📋 Submission ID: $SUBMISSION_ID"
    echo ""
    
    # Wait for completion
    xcrun notarytool wait "$SUBMISSION_ID" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$TEAM_ID"
    
    if [ $? -eq 0 ]; then
      echo ""
      echo "✅ Notarization complete!"
      echo ""
      echo "📌 Next step: Staple the notarization ticket:"
      echo "   npm run notarize:staple"
    fi
    ;;
esac
