#!/bin/bash

APP_PATH="apps/electron/dist/mac-arm64/Nexus Countdown.app"

# Check if universal binary exists first
if [ -f "dist/mac/Nexus Countdown.app/Contents/MacOS/Nexus Countdown" ]; then
  APP_PATH="dist/mac/Nexus Countdown.app"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "❌ App not found. Run mas:electron:build first."
  exit 1
fi

echo "=== MAS .pkg Verification Summary ==="
echo "App: $APP_PATH"
echo ""

echo "1. ENTITLEMENTS:"
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | plutil -p - 2>/dev/null)
if echo "$ENTITLEMENTS" | grep -q "T6YG6KXA9D.com.nexuscountdown"; then
  echo "✅ Entitlements present and correct"
  echo "   - application-identifier: T6YG6KXA9D.com.nexuscountdown"
  echo "   - team-identifier: T6YG6KXA9D"
  echo "   - app-sandbox: true"
else
  echo "❌ Entitlements missing or incorrect"
fi
echo ""

echo "2. ARCHITECTURE:"
BINARY="$APP_PATH/Contents/MacOS/Nexus Countdown"
ARCH_INFO=$(lipo -info "$BINARY" 2>&1 || file "$BINARY")
if echo "$ARCH_INFO" | grep -qE "(arm64.*x86_64|x86_64.*arm64|universal)"; then
  echo "✅ Universal binary (arm64 + x86_64)"
  echo "   $ARCH_INFO"
elif echo "$ARCH_INFO" | grep -q "Non-fat file"; then
  echo "⚠️  Binary is NOT universal"
  echo "   Current: $ARCH_INFO"
  echo "   Expected: arm64 + x86_64 (universal)"
else
  echo "ℹ️  $ARCH_INFO"
fi
echo ""

echo "3. PROVISIONING PROFILE & IDs:"
PROV="$APP_PATH/Contents/embedded.provisionprofile"
if [ -f "$PROV" ]; then
  echo "✅ Provisioning profile embedded"
  PROV_TEAM=$(security cms -D -i "$PROV" 2>/dev/null | plutil -p - | grep -A 1 "TeamIdentifier" | tail -1 | grep -o "T6YG6KXA9D" || echo "")
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
  CODE_TEAM=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | plutil -p - | grep "team-identifier" | head -1 | grep -o "T6YG6KXA9D" || echo "")
  
  if [ "$PROV_TEAM" = "T6YG6KXA9D" ] && [ "$BUNDLE_ID" = "com.nexuscountdown" ] && [ "$CODE_TEAM" = "T6YG6KXA9D" ]; then
    echo "✅ All IDs align correctly:"
    echo "   - Profile Team ID: $PROV_TEAM"
    echo "   - Bundle ID: $BUNDLE_ID"
    echo "   - Code Signature Team ID: $CODE_TEAM"
  else
    echo "❌ ID mismatch detected"
    echo "   - Profile Team ID: $PROV_TEAM"
    echo "   - Bundle ID: $BUNDLE_ID"
    echo "   - Code Signature Team ID: $CODE_TEAM"
  fi
else
  echo "❌ Provisioning profile NOT found"
fi
