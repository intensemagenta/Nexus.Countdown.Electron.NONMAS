const fs = require('fs');
const path = require('path');

const distDir = path.join(__dirname, '..', 'dist');

let passed = 0;
let failed = 0;

function check(description, condition, details = '') {
  if (condition) {
    console.log(`✓ PASS: ${description}${details ? ' - ' + details : ''}`);
    passed++;
  } else {
    console.log(`✗ FAIL: ${description}${details ? ' - ' + details : ''}`);
    failed++;
  }
}

// Find the actual app bundle (electron-builder may create architecture-specific directories)
function findAppBundle() {
  if (!fs.existsSync(distDir)) {
    return null;
  }
  
  const entries = fs.readdirSync(distDir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const subDir = path.join(distDir, entry.name);
      const subEntries = fs.readdirSync(subDir, { withFileTypes: true });
      for (const subEntry of subEntries) {
        if (subEntry.isDirectory() && subEntry.name.endsWith('.app')) {
          return path.join(subDir, subEntry.name);
        }
      }
    }
  }
  return null;
}

console.log('Verifying Electron bundle...\n');

// Find the actual app bundle location
const macAppPath = findAppBundle();
check('App bundle exists', macAppPath !== null, macAppPath || 'Not found');

if (macAppPath) {
  const resourcesPath = path.join(macAppPath, 'Contents', 'Resources');
  const asarPath = path.join(resourcesPath, 'app.asar');
  const unpackedPath = path.join(resourcesPath, 'app');
  
  // Check if app.asar exists (electron-builder creates this)
  check('app.asar exists', fs.existsSync(asarPath), asarPath);
  
  // Check if unpacked directory exists (as fallback, electron-builder may use unpacked files)
  // Note: electron-builder may use app.asar OR unpacked files depending on configuration
  const appExists = fs.existsSync(asarPath) || fs.existsSync(unpackedPath);
  check('App package exists (asar or unpacked)', appExists);
  
  // Try to check for index.html in unpacked directory if it exists
  if (fs.existsSync(unpackedPath)) {
    const indexHtmlPath = path.join(unpackedPath, 'web', 'index.html');
    check('index.html exists in unpacked app', fs.existsSync(indexHtmlPath), indexHtmlPath);
  } else if (fs.existsSync(asarPath)) {
    // If using asar, we can't easily inspect without asar module
    // Just note that asar exists and contains the app
    console.log('ℹ INFO: App is packaged as asar (normal). To inspect contents, install asar: npm install -g asar');
  }
}

// Check for DMG file
const dmgFiles = fs.readdirSync(distDir).filter(f => f.endsWith('.dmg'));
check('DMG file exists', dmgFiles.length > 0, dmgFiles.length > 0 ? `Found: ${dmgFiles[0]}` : 'No DMG found in dist/');

console.log(`\nSummary: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);

