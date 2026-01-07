#!/usr/bin/env node
/**
 * Locates the latest MAS build .app bundle under apps/electron/dist
 * Prints the absolute path to stdout, fails with error if not found
 */

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '../..');
const ELECTRON_DIR = path.join(REPO_ROOT, 'apps', 'electron');
const DIST_DIR = path.join(ELECTRON_DIR, 'dist');

if (!fs.existsSync(DIST_DIR)) {
  console.error(`❌ ERROR: dist directory not found at ${DIST_DIR}`);
  process.exit(1);
}

// Priority order for finding the MAS app bundle
// electron-builder typically outputs to dist/mac/ for dir builds
const SEARCH_PATTERNS = [
  'dist/mas/**/*.app',
  'dist/mac/**/*.app',
  'dist/mac-universal/**/*.app',
  'dist/mac-arm64/**/*.app',
  'dist/mac-x64/**/*.app',
];

let foundApp = null;
const appName = 'Nexus Countdown.app'; // Based on productName in package.json

// Try direct paths first (faster)
const directPaths = [
  path.join(DIST_DIR, 'mas', appName),
  path.join(DIST_DIR, 'mac', appName),  // Universal build (x64 + arm64)
  path.join(DIST_DIR, 'mac-universal', appName),
  path.join(DIST_DIR, 'mas-arm64', appName),  // MAS-specific builds
  path.join(DIST_DIR, 'mas-x64', appName),
];

for (const appPath of directPaths) {
  if (fs.existsSync(appPath) && fs.statSync(appPath).isDirectory()) {
    foundApp = path.resolve(appPath);
    break;
  }
}

// If not found, search recursively
if (!foundApp) {
  try {
    // Find all .app bundles in dist
    const result = execSync(
      `find "${DIST_DIR}" -name "${appName}" -type d -maxdepth 3 2>/dev/null`,
      { encoding: 'utf-8', cwd: REPO_ROOT }
    );
    
    const apps = result.trim().split('\n').filter(Boolean);
    if (apps.length > 0) {
      // Prefer mas > mac > others
      const sorted = apps.sort((a, b) => {
        const aPriority = a.includes('/mas/') ? 0 : a.includes('/mac/') ? 1 : 2;
        const bPriority = b.includes('/mas/') ? 0 : b.includes('/mac/') ? 1 : 2;
        return aPriority - bPriority;
      });
      foundApp = path.resolve(sorted[0]);
    }
  } catch (err) {
    // find command failed or no results
  }
}

if (!foundApp || !fs.existsSync(foundApp)) {
  console.error(`❌ ERROR: Could not find MAS app bundle "${appName}"`);
  console.error(`   Searched in: ${DIST_DIR}`);
  console.error(`   Please run the MAS build first.`);
  process.exit(1);
}

// Verify it's actually an app bundle
const infoPlist = path.join(foundApp, 'Contents', 'Info.plist');
if (!fs.existsSync(infoPlist)) {
  console.error(`❌ ERROR: Found app bundle but missing Info.plist: ${foundApp}`);
  process.exit(1);
}

console.log(foundApp);

