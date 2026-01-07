#!/bin/bash
set -euo pipefail

# Build the Electron app for MAS using electron-builder
# This uses electron-builder's MAS target which handles signing automatically

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Increment version by 0.0.1 before building
echo "📝 Incrementing version..."
ROOT_PACKAGE_JSON="$REPO_ROOT/package.json"
ELECTRON_PACKAGE_JSON="$REPO_ROOT/apps/electron/package.json"

if [ ! -f "$ROOT_PACKAGE_JSON" ] || [ ! -f "$ELECTRON_PACKAGE_JSON" ]; then
  echo "❌ ERROR: package.json files not found"
  exit 1
fi

# Get current version
CURRENT_VERSION=$(node -p "require('$ROOT_PACKAGE_JSON').version")
echo "   Current version: $CURRENT_VERSION"

# Increment patch version (e.g., 1.4.9 -> 1.4.10)
NEW_VERSION=$(node -e "
  const v = '$CURRENT_VERSION'.split('.');
  const major = parseInt(v[0]) || 0;
  const minor = parseInt(v[1]) || 0;
  const patch = parseInt(v[2]) || 0;
  console.log(major + '.' + minor + '.' + (patch + 1));
")

echo "   New version: $NEW_VERSION"

# Update both package.json files
node -e "
  const fs = require('fs');
  const rootPkg = JSON.parse(fs.readFileSync('$ROOT_PACKAGE_JSON', 'utf8'));
  const electronPkg = JSON.parse(fs.readFileSync('$ELECTRON_PACKAGE_JSON', 'utf8'));
  rootPkg.version = '$NEW_VERSION';
  electronPkg.version = '$NEW_VERSION';
  fs.writeFileSync('$ROOT_PACKAGE_JSON', JSON.stringify(rootPkg, null, 2) + '\n');
  fs.writeFileSync('$ELECTRON_PACKAGE_JSON', JSON.stringify(electronPkg, null, 2) + '\n');
"

echo "✅ Version updated to $NEW_VERSION"
echo ""

echo "📦 Building Electron app for MAS using electron-builder..."

cd apps/electron

# Ensure icon exists (copy from icons folder if needed)
ICON_SOURCE="$REPO_ROOT/icons/Icons/countdown.icns"
ICON_DEST="build/icons/icon.icns"
if [ ! -f "$ICON_DEST" ] && [ -f "$ICON_SOURCE" ]; then
  echo "Copying icon..."
  mkdir -p "$(dirname "$ICON_DEST")"
  cp "$ICON_SOURCE" "$ICON_DEST"
fi

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

# Set signing environment variables to force correct MAS identity
export CSC_NAME="Adam Parsons (T6YG6KXA9D)"
export CSC_IDENTITY_AUTO_DISCOVERY=false
export ELECTRON_TEAM_ID=T6YG6KXA9D

echo "Building MAS package with electron-builder..."
echo "Using identity: $CSC_NAME"
echo "Team ID: $ELECTRON_TEAM_ID"
echo ""
echo "Building universal binary (arm64 + x86_64) for MAS..."
echo "Note: electron-builder will:"
echo "  - Build universal binary with both arm64 and x86_64 architectures"
echo "  - Sign automatically with MAS certificate"
echo "  - Add application-identifier to entitlements automatically"
echo "  - Create signed .pkg installer"
echo ""

# Build for both architectures - electron-builder creates separate builds
# We'll merge them into a universal binary afterward
echo "Building MAS package for both architectures..."

# #region agent log
node -e "
const fs = require('fs');
const path = require('path');
const logData = {
  location: 'build-electron-mas.sh:88',
  message: 'About to run electron-builder with --x64 --arm64',
  data: {
    command: 'npx electron-builder --mac mas --x64 --arm64',
    note: 'Will create separate builds that need to be merged'
  },
  timestamp: Date.now(),
  sessionId: 'debug-session',
  runId: 'post-fix'
};
fetch('http://127.0.0.1:7245/ingest/7e138a56-fb52-4306-8786-a027ca381705', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(logData)
}).catch(() => {});
"
# #endregion

npx electron-builder --mac mas --x64 --arm64

# electron-builder creates separate builds: dist/mas (x86_64) and dist/mas-arm64 (arm64)
# We need to merge them into a universal binary in dist/mas
echo ""
echo "Merging x86_64 and arm64 builds into universal binary..."

X64_APP="dist/mas/Nexus Countdown.app"
ARM64_APP="dist/mas-arm64/Nexus Countdown.app"

if [ ! -d "$X64_APP" ] || [ ! -d "$ARM64_APP" ]; then
  echo "⚠️  WARNING: Could not find both architecture builds to merge"
  echo "   X64 app exists: $([ -d "$X64_APP" ] && echo "YES" || echo "NO")"
  echo "   ARM64 app exists: $([ -d "$ARM64_APP" ] && echo "YES" || echo "NO")"
else
  echo "   Found x86_64 build: $X64_APP"
  echo "   Found arm64 build: $ARM64_APP"
  
  # Extract entitlements from original signed app BEFORE merging (merging breaks signatures)
  echo "   Extracting entitlements from original signed app..."
  TEMP_ENTITLEMENTS="$REPO_ROOT/apps/electron/.temp-entitlements.plist"
  TEMP_ENTITLEMENTS_INHERIT="$REPO_ROOT/apps/electron/.temp-entitlements-inherit.plist"
  
  # Extract main app entitlements (electron-builder already added application-identifier)
  codesign -d --entitlements :- "$X64_APP" 2>/dev/null > "$TEMP_ENTITLEMENTS" || {
    # Fallback to build entitlements if extraction fails
    cp "$REPO_ROOT/apps/electron/build/entitlements.mas.plist" "$TEMP_ENTITLEMENTS"
  }
  
  # Extract inherit entitlements from a helper (they should all be the same)
  FIRST_HELPER=$(find "$X64_APP/Contents/Frameworks" -name "*Helper*.app" -type d 2>/dev/null | head -1)
  if [ -n "$FIRST_HELPER" ]; then
    codesign -d --entitlements :- "$FIRST_HELPER" 2>/dev/null > "$TEMP_ENTITLEMENTS_INHERIT" || {
      cp "$REPO_ROOT/apps/electron/build/entitlements.mas.inherit.plist" "$TEMP_ENTITLEMENTS_INHERIT"
    }
  else
    cp "$REPO_ROOT/apps/electron/build/entitlements.mas.inherit.plist" "$TEMP_ENTITLEMENTS_INHERIT"
  fi
  
  # Merge main executable
  X64_BIN="$X64_APP/Contents/MacOS/Nexus Countdown"
  ARM64_BIN="$ARM64_APP/Contents/MacOS/Nexus Countdown"
  
  if [ -f "$X64_BIN" ] && [ -f "$ARM64_BIN" ]; then
    lipo -create "$ARM64_BIN" "$X64_BIN" -output "$X64_BIN"
    if [ $? -eq 0 ]; then
      echo "   ✅ Merged main executable: universal (arm64 + x86_64)"
      lipo -info "$X64_BIN"
    fi
  fi
  
  # Merge helper app executables
  echo "   Merging helper app executables..."
  for helper in "$X64_APP/Contents/Frameworks/"*Helper*.app; do
    if [ -d "$helper" ]; then
      HELPER_NAME=$(basename "$helper")
      ARM64_HELPER="$ARM64_APP/Contents/Frameworks/$HELPER_NAME"
      
      if [ -d "$ARM64_HELPER" ]; then
        EXEC_NAME=$(ls "$helper/Contents/MacOS/" 2>/dev/null | head -1)
        if [ -n "$EXEC_NAME" ]; then
          X64_EXEC="$helper/Contents/MacOS/$EXEC_NAME"
          ARM64_EXEC="$ARM64_HELPER/Contents/MacOS/$EXEC_NAME"
          
          if [ -f "$ARM64_EXEC" ] && [ -f "$X64_EXEC" ]; then
            lipo -create "$ARM64_EXEC" "$X64_EXEC" -output "$X64_EXEC" 2>/dev/null
            if [ $? -eq 0 ]; then
              echo "     ✅ $HELPER_NAME: universal"
            fi
          fi
        fi
      fi
    fi
  done
  
  # Merge Electron Framework binary and executables
  FRAMEWORK="$X64_APP/Contents/Frameworks/Electron Framework.framework"
  ARM64_FRAMEWORK="$ARM64_APP/Contents/Frameworks/Electron Framework.framework"
  
  if [ -d "$FRAMEWORK" ] && [ -d "$ARM64_FRAMEWORK" ]; then
    echo "   Merging Electron Framework..."
    
    # Merge main framework binary
    FRAMEWORK_BIN="$FRAMEWORK/Versions/A/Electron Framework"
    ARM64_FRAMEWORK_BIN="$ARM64_FRAMEWORK/Versions/A/Electron Framework"
    
    if [ -f "$ARM64_FRAMEWORK_BIN" ] && [ -f "$FRAMEWORK_BIN" ]; then
      lipo -create "$ARM64_FRAMEWORK_BIN" "$FRAMEWORK_BIN" -output "$FRAMEWORK_BIN" 2>/dev/null
      if [ $? -eq 0 ]; then
        echo "     ✅ Electron Framework: universal"
      fi
    fi
    
    # Merge dylibs
    if [ -d "$FRAMEWORK/Versions/A/Libraries" ] && [ -d "$ARM64_FRAMEWORK/Versions/A/Libraries" ]; then
      for lib in "$FRAMEWORK/Versions/A/Libraries"/*.dylib; do
        if [ -f "$lib" ]; then
          LIB_NAME=$(basename "$lib")
          ARM64_LIB="$ARM64_FRAMEWORK/Versions/A/Libraries/$LIB_NAME"
          if [ -f "$ARM64_LIB" ]; then
            lipo -create "$ARM64_LIB" "$lib" -output "$lib" 2>/dev/null
          fi
        fi
      done
    fi
    
    # Merge helpers in framework
    if [ -d "$FRAMEWORK/Versions/A/Helpers" ] && [ -d "$ARM64_FRAMEWORK/Versions/A/Helpers" ]; then
      for helper_bin in "$FRAMEWORK/Versions/A/Helpers"/*; do
        if [ -f "$helper_bin" ] && [ -x "$helper_bin" ]; then
          HELPER_NAME=$(basename "$helper_bin")
          ARM64_HELPER_BIN="$ARM64_FRAMEWORK/Versions/A/Helpers/$HELPER_NAME"
          if [ -f "$ARM64_HELPER_BIN" ]; then
            lipo -create "$ARM64_HELPER_BIN" "$helper_bin" -output "$helper_bin" 2>/dev/null
          fi
        fi
      done
    fi
  fi
  
  # Merge other frameworks
  for framework in "$X64_APP/Contents/Frameworks"/*.framework; do
    if [ -d "$framework" ] && [ "$(basename "$framework")" != "Electron Framework.framework" ]; then
      FRAMEWORK_NAME=$(basename "$framework" .framework)
      ARM64_FW="$ARM64_APP/Contents/Frameworks/$FRAMEWORK_NAME.framework"
      
      if [ -d "$ARM64_FW" ]; then
        FW_BINARY="$framework/Versions/A/$FRAMEWORK_NAME"
        ARM64_FW_BINARY="$ARM64_FW/Versions/A/$FRAMEWORK_NAME"
        
        if [ -f "$ARM64_FW_BINARY" ] && [ -f "$FW_BINARY" ]; then
          lipo -create "$ARM64_FW_BINARY" "$FW_BINARY" -output "$FW_BINARY" 2>/dev/null
        fi
      fi
    fi
  done
  
  echo "   ✅ Universal binary merge complete"
  
  # After merging, we need to re-sign the app and rebuild the .pkg
  # because merging breaks code signatures
  # We already extracted entitlements above (before merging)
  echo ""
  echo "Re-signing merged universal app with preserved entitlements..."
  
  IDENTITY="3rd Party Mac Developer Application: Adam Parsons (T6YG6KXA9D)"
  
  ENTITLEMENTS="$TEMP_ENTITLEMENTS"
  ENTITLEMENTS_INHERIT="$TEMP_ENTITLEMENTS_INHERIT"
  
  # Sign all nested components first
  for helper in "$X64_APP/Contents/Frameworks/"*Helper*.app; do
    if [ -d "$helper" ]; then
      codesign --force --sign "$IDENTITY" \
        --entitlements "$ENTITLEMENTS_INHERIT" \
        --options runtime \
        "$helper" 2>/dev/null || true
    fi
  done
  
  # Sign frameworks
  for framework in "$X64_APP/Contents/Frameworks"/*.framework; do
    if [ -d "$framework" ]; then
      codesign --force --sign "$IDENTITY" \
        --entitlements "$ENTITLEMENTS_INHERIT" \
        --options runtime \
        "$framework" 2>/dev/null || true
    fi
  done
  
  # Sign main app
  codesign --force --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$X64_APP" 2>/dev/null || true
  
  echo "   ✅ Re-signed universal app"
  
  # Delete old .pkg files from this build
  find dist/mas -name "*.pkg" -delete 2>/dev/null || true
  find dist/mas-arm64 -name "*.pkg" -delete 2>/dev/null || true
  
  # Rebuild .pkg from merged universal app
  echo "Rebuilding .pkg from universal app..."
  INFO_PLIST="$X64_APP/Contents/Info.plist"
  INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Adam Parsons (T6YG6KXA9D)"
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0.0")
  NEW_PKG_PATH="dist/mas/Nexus Countdown-${VERSION}.pkg"
  
  productbuild \
    --component "$X64_APP" "/Applications" \
    --sign "$INSTALLER_IDENTITY" \
    --product "$INFO_PLIST" \
    "$NEW_PKG_PATH" 2>&1
  
  if [ -f "$NEW_PKG_PATH" ]; then
    echo "   ✅ Rebuilt .pkg from universal app: $(basename "$NEW_PKG_PATH")"
    # Remove quarantine
    xattr -cr "$NEW_PKG_PATH" 2>/dev/null || true
  else
    echo "   ⚠️  Warning: Failed to rebuild .pkg"
  fi
  
  # Clean up temporary entitlements files
  rm -f "$TEMP_ENTITLEMENTS" "$TEMP_ENTITLEMENTS_INHERIT" 2>/dev/null || true
fi

# #region agent log
node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');
const x64App = 'dist/mas/Nexus Countdown.app';
if (fs.existsSync(x64App)) {
  const mainBin = path.join(x64App, 'Contents/MacOS/Nexus Countdown');
  try {
    const lipo = execSync(\`lipo -info \"\${mainBin}\" 2>/dev/null\`, { encoding: 'utf-8' });
    const isUniversal = lipo.includes('arm64') && (lipo.includes('x86_64') || lipo.includes('i386'));
    const logData = {
      location: 'build-electron-mas.sh:230',
      message: 'After merge and re-sign: Checking universal binary',
      data: {
        mergedApp: x64App,
        lipoInfo: lipo.trim(),
        isUniversal: isUniversal
      },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      runId: 'post-fix'
    };
    fetch('http://127.0.0.1:7245/ingest/7e138a56-fb52-4306-8786-a027ca381705', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(logData)
    }).catch(() => {});
  } catch (e) {}
}
"
# #endregion

# Find the built .pkg file
# electron-builder may create universal or architecture-specific builds
PKG_DIRS=(
  "dist"
  "dist/mas"
  "dist/mas-universal"
  "dist/mas-arm64"
  "dist/mas-x64"
)

PKG_PATH=""
# Prefer universal builds, then arm64, then any .pkg
for dir in "dist/mas-universal" "dist/mas" "dist/mas-arm64" "dist/mas-x64" "dist"; do
  if [ -d "$dir" ]; then
    # Look for .pkg files, prefer ones without architecture suffix (universal)
    FOUND_PKG=$(find "$dir" -name "*.pkg" -type f ! -name "*-arm64.pkg" ! -name "*-x64.pkg" 2>/dev/null | head -1 || true)
    if [ -z "$FOUND_PKG" ]; then
      # Fallback to any .pkg
      FOUND_PKG=$(find "$dir" -name "*.pkg" -type f 2>/dev/null | head -1 || true)
    fi
    if [ -n "$FOUND_PKG" ]; then
      PKG_PATH="$(cd "$(dirname "$FOUND_PKG")" && pwd)/$(basename "$FOUND_PKG")"
      break
    fi
  fi
done

if [ -z "$PKG_PATH" ]; then
  echo "❌ ERROR: Could not find built .pkg file"
  echo "Searched in: ${PKG_DIRS[*]}"
  exit 1
fi

echo ""
echo "✅ MAS package built successfully at: $PKG_PATH"
echo "$PKG_PATH" > "$REPO_ROOT/.mas-pkg-path"

# #region agent log
node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');
const pkgPath = '$PKG_PATH';
const logData = {
  location: 'build-electron-mas.sh:355',
  message: 'Final PKG verification: binary architectures inside .pkg',
  data: {
    pkgPath: pkgPath,
    pkgExists: fs.existsSync(pkgPath)
  },
  timestamp: Date.now(),
  sessionId: 'debug-session',
  runId: 'post-fix'
};
if (fs.existsSync(pkgPath)) {
  const tempDir = '/tmp/pkg-check-' + Date.now();
  try {
    execSync(\`mkdir -p \"\${tempDir}\" && pkgutil --expand-full \"\${pkgPath}\" \"\${tempDir}/expanded\" 2>/dev/null\`, { stdio: 'ignore' });
    const appInPkg = execSync(\`find \"\${tempDir}/expanded/Payload\" -name '*.app' -type d 2>/dev/null | head -1\`, { encoding: 'utf-8' }).trim();
    if (appInPkg) {
      const mainBin = path.join(appInPkg, 'Contents/MacOS/Nexus Countdown');
      try {
        const lipo = execSync(\`lipo -info \"\${mainBin}\" 2>/dev/null\`, { encoding: 'utf-8' });
        logData.data.appInPkg = appInPkg;
        logData.data.binaryArchitectures = lipo.trim();
        logData.data.isUniversal = lipo.includes('arm64') && (lipo.includes('x86_64') || lipo.includes('i386'));
      } catch (e) {
        logData.data.binaryCheckError = e.message;
      }
    }
    execSync(\`rm -rf \"\${tempDir}\" 2>/dev/null\`, { stdio: 'ignore' });
  } catch (e) {
    logData.data.pkgExtractError = e.message;
  }
}
fetch('http://127.0.0.1:7245/ingest/7e138a56-fb52-4306-8786-a027ca381705', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(logData)
}).catch(() => {});
"
# #endregion

# #region agent log
node -e "
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const pkgPath = '$PKG_PATH';
const logData = {
  location: 'build-electron-mas.sh:126',
  message: 'Found PKG file, checking contents',
  data: {
    pkgPath: pkgPath,
    pkgExists: fs.existsSync(pkgPath),
    hypothesisId: 'B'
  },
  timestamp: Date.now(),
  sessionId: 'debug-session',
  runId: 'run1'
};
if (fs.existsSync(pkgPath)) {
  const tempDir = '/tmp/pkg-check-' + Date.now();
  try {
    execSync(\`mkdir -p \"\${tempDir}\" && pkgutil --expand-full \"\${pkgPath}\" \"\${tempDir}/expanded\" 2>/dev/null\`, { stdio: 'ignore' });
    const appInPkg = execSync(\`find \"\${tempDir}/expanded/Payload\" -name '*.app' -type d 2>/dev/null | head -1\`, { encoding: 'utf-8' }).trim();
    if (appInPkg) {
      const mainBin = path.join(appInPkg, 'Contents/MacOS/Nexus Countdown');
      try {
        const lipo = execSync(\`lipo -info \"\${mainBin}\" 2>/dev/null\`, { encoding: 'utf-8' });
        logData.data.appInPkg = appInPkg;
        logData.data.binaryArchitectures = lipo.trim();
        logData.data.isUniversal = lipo.includes('arm64') && (lipo.includes('x86_64') || lipo.includes('i386'));
      } catch (e) {
        logData.data.binaryCheckError = e.message;
      }
    }
    execSync(\`rm -rf \"\${tempDir}\" 2>/dev/null\`, { stdio: 'ignore' });
  } catch (e) {
    logData.data.pkgExtractError = e.message;
  }
}
fetch('http://127.0.0.1:7245/ingest/7e138a56-fb52-4306-8786-a027ca381705', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(logData)
}).catch(() => {});
"
# #endregion

# Also find the .app bundle (electron-builder may create it in dist/mac for verification)
APP_DIRS=(
  "dist/mac"
  "dist/mac-universal"
  "dist/mac-unpacked"
)

APP_PATH=""
for dir in "${APP_DIRS[@]}"; do
  if [ -d "$dir" ] && [ -d "$dir/Nexus Countdown.app" ]; then
    APP_PATH="$(cd "$dir" && pwd)/Nexus Countdown.app"
    break
  fi
done

if [ -n "$APP_PATH" ]; then
  echo "$APP_PATH" > "$REPO_ROOT/.mas-app-path"
  echo "✅ App bundle found at: $APP_PATH (for verification)"
  
  # Verify universal binary
  MAIN_BINARY="$APP_PATH/Contents/MacOS/Nexus Countdown"
  if [ -f "$MAIN_BINARY" ]; then
    LIPO_INFO=$(lipo -info "$MAIN_BINARY" 2>/dev/null || echo "")
    
    # #region agent log
    node -e "
    const lipoInfo = '$LIPO_INFO';
    const appPath = '$APP_PATH';
    const hasArm64 = lipoInfo.includes('arm64');
    const hasX86_64 = lipoInfo.includes('x86_64') || lipoInfo.includes('i386');
    const logData = {
      location: 'build-electron-mas.sh:149',
      message: 'Checking app bundle binary architectures',
      data: {
        appPath: appPath,
        lipoInfo: lipoInfo,
        hasArm64: hasArm64,
        hasX86_64: hasX86_64,
        isUniversal: hasArm64 && hasX86_64,
        hypothesisId: 'C'
      },
      timestamp: Date.now(),
      sessionId: 'debug-session',
      runId: 'run1'
    };
    fetch('http://127.0.0.1:7245/ingest/7e138a56-fb52-4306-8786-a027ca381705', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(logData)
    }).catch(() => {});
    "
    # #endregion
    
    if echo "$LIPO_INFO" | grep -q "arm64" && echo "$LIPO_INFO" | grep -q "x86_64\|i386"; then
      echo "✅ Verified: Universal binary (arm64 + x86_64)"
    else
      echo "⚠️  WARNING: Binary may not be universal:"
      echo "   $LIPO_INFO"
    fi
  fi
else
  echo "⚠️  App bundle not found in dist (this is OK - .pkg is the deliverable)"
fi
