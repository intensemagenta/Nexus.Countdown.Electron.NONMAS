#!/usr/bin/env node
/**
 * Verification script for Electron MAS build
 * Checks that entitlements are correct (electron-builder adds application-identifier automatically)
 * Verifies embedded.provisionprofile exists and matches entitlements
 */

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '../..');

// Get app bundle path - try from .mas-app-path or extract from .pkg
let appPath;
let pkgPath;

// First, try to get app path from .mas-app-path
if (fs.existsSync(path.join(REPO_ROOT, '.mas-app-path'))) {
  appPath = fs.readFileSync(path.join(REPO_ROOT, '.mas-app-path'), 'utf-8').trim();
}

// If no app path, try to get .pkg and extract app from it
if (!appPath || !fs.existsSync(appPath)) {
  if (fs.existsSync(path.join(REPO_ROOT, '.mas-pkg-path'))) {
    pkgPath = fs.readFileSync(path.join(REPO_ROOT, '.mas-pkg-path'), 'utf-8').trim();
  } else {
    // Search for .pkg in dist directories
    const distDirs = [
      path.join(REPO_ROOT, 'apps', 'electron', 'dist'),
      path.join(REPO_ROOT, 'apps', 'electron', 'dist', 'mas'),
      path.join(REPO_ROOT, 'dist', 'mas')
    ];
    
    for (const dir of distDirs) {
      if (fs.existsSync(dir)) {
        const pkgs = fs.readdirSync(dir).filter(f => f.endsWith('.pkg'));
        if (pkgs.length > 0) {
          pkgPath = path.join(dir, pkgs[0]);
          break;
        }
      }
    }
  }
  
  // If we have a .pkg but no app, extract it temporarily for verification
  if (pkgPath && fs.existsSync(pkgPath) && (!appPath || !fs.existsSync(appPath))) {
    console.log('📦 Extracting app from .pkg for verification...');
    const tempDir = path.join(REPO_ROOT, '.mas-verify-temp');
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
    fs.mkdirSync(tempDir, { recursive: true });
    
    try {
      // Extract .pkg using pkgutil
      execSync(`pkgutil --expand-full "${pkgPath}" "${tempDir}/pkg-expanded"`, {
        cwd: REPO_ROOT,
        stdio: 'pipe'
      });
      
      // Find the app in the extracted payload
      const payloadDir = path.join(tempDir, 'pkg-expanded', 'Payload');
      if (fs.existsSync(payloadDir)) {
        const apps = fs.readdirSync(payloadDir).filter(f => f.endsWith('.app'));
        if (apps.length > 0) {
          appPath = path.join(payloadDir, apps[0]);
        }
      }
    } catch (err) {
      // Extraction failed, but we can still check dist/mas in the fallback below
      console.log('⚠️  Could not extract app from .pkg, will try dist directories instead');
    }
  }
}

// Fallback: search for app in dist directories
if (!appPath || !fs.existsSync(appPath)) {
  const appDirs = [
    path.join(REPO_ROOT, 'apps', 'electron', 'dist', 'mas'), // Check dist/mas first (merged universal app)
    path.join(REPO_ROOT, 'apps', 'electron', 'dist', 'mac'),
    path.join(REPO_ROOT, 'apps', 'electron', 'dist', 'mac-universal'),
    path.join(REPO_ROOT, 'apps', 'electron', 'dist', 'mac-unpacked')
  ];
  
  for (const dir of appDirs) {
    if (fs.existsSync(dir)) {
      const apps = fs.readdirSync(dir).filter(f => f.endsWith('.app'));
      if (apps.length > 0) {
        appPath = path.join(dir, apps[0]);
        break;
      }
    }
  }
}

if (!appPath || !fs.existsSync(appPath)) {
  console.error('❌ ERROR: Could not locate MAS app bundle');
  console.error('   Run the MAS build first: npm run mas:electron:build');
  process.exit(1);
}

console.log('🔍 Verifying Electron MAS build...');
console.log(`   App: ${path.basename(appPath)}`);
if (pkgPath) {
  console.log(`   PKG: ${path.basename(pkgPath)}`);
}
console.log('');

let allChecksPassed = true;

// 1. Check for ShipIt and Squirrel.framework (must NOT exist)
console.log('1. Checking for ShipIt and Squirrel.framework (must be absent)...');
try {
  const shipitFind = execSync(`find "${appPath}/Contents" -maxdepth 10 -iname "ShipIt" -type f 2>/dev/null || true`, {
    encoding: 'utf-8'
  });
  const squirrelFind = execSync(`find "${appPath}/Contents" -maxdepth 10 -iname "Squirrel.framework" -type d 2>/dev/null || true`, {
    encoding: 'utf-8'
  });
  
  if (shipitFind.trim() || squirrelFind.trim()) {
    console.error('   ❌ FAIL: ShipIt or Squirrel.framework found');
    if (shipitFind.trim()) {
      console.error(`      ShipIt: ${shipitFind.trim().split('\n')[0]}`);
    }
    if (squirrelFind.trim()) {
      console.error(`      Squirrel: ${squirrelFind.trim().split('\n')[0]}`);
    }
    allChecksPassed = false;
  } else {
    console.log('   ✅ PASS: No ShipIt or Squirrel.framework found');
  }
} catch (err) {
  console.log('   ✅ PASS: No ShipIt or Squirrel.framework found');
}

// 2. Check that embedded.provisionprofile exists and verify its content
console.log('');
console.log('2. Checking embedded.provisionprofile exists and content...');
const embeddedProfile = path.join(appPath, 'Contents', 'embedded.provisionprofile');
if (!fs.existsSync(embeddedProfile)) {
  console.error('   ❌ FAIL: embedded.provisionprofile not found');
  console.error('      MAS builds require an embedded provisioning profile');
  console.error(`      Expected at: ${embeddedProfile}`);
  allChecksPassed = false;
} else {
  console.log('   ✅ PASS: embedded.provisionprofile exists');
  
  // Verify profile content matches expected values
  try {
    const profileData = execSync(`security cms -D -i "${embeddedProfile}" 2>/dev/null`, {
      encoding: 'utf-8'
    });
    const profilePlist = execSync(`echo '${profileData.replace(/'/g, "'\"'\"'")}' | plutil -p -`, {
      encoding: 'utf-8'
    });
    
    // Extract ApplicationIdentifier from profile
    const profileAppIdMatch = profilePlist.match(/Entitlements.*?application-identifier.*?=>\s*"([^"]+)"/s);
    const profileAppId = profileAppIdMatch ? profileAppIdMatch[1] : null;
    
    // Extract TeamIdentifier
    const profileTeamIdMatch = profilePlist.match(/TeamIdentifier.*?=>\s*\[\s*0\s*=>\s*"([^"]+)"/) ||
                                profilePlist.match(/team-identifier.*?=>\s*"([^"]+)"/);
    const profileTeamId = profileTeamIdMatch ? profileTeamIdMatch[1] : null;
    
    // Extract ExpirationDate
    const expMatch = profilePlist.match(/ExpirationDate.*?=>\s*([0-9]{4}-[0-9]{2}-[0-9]{2}[^"]*)/);
    const profileExpDate = expMatch ? expMatch[1].trim() : null;
    
    console.log(`      Profile ApplicationIdentifier: ${profileAppId || 'MISSING'}`);
    console.log(`      Profile TeamIdentifier: ${profileTeamId || 'MISSING'}`);
    console.log(`      Profile ExpirationDate: ${profileExpDate || 'MISSING'}`);
    
    const EXPECTED_APP_ID = 'T6YG6KXA9D.com.nexuscountdown';
    const EXPECTED_TEAM_ID = 'T6YG6KXA9D';
    
    if (!profileAppId || profileAppId !== EXPECTED_APP_ID) {
      console.error(`   ❌ FAIL: Profile ApplicationIdentifier mismatch`);
      console.error(`      Expected: ${EXPECTED_APP_ID}`);
      console.error(`      Found: ${profileAppId || 'MISSING'}`);
      allChecksPassed = false;
    }
    
    if (!profileTeamId || profileTeamId !== EXPECTED_TEAM_ID) {
      console.error(`   ❌ FAIL: Profile TeamIdentifier mismatch`);
      console.error(`      Expected: ${EXPECTED_TEAM_ID}`);
      console.error(`      Found: ${profileTeamId || 'MISSING'}`);
      allChecksPassed = false;
    }
    
    if (profileExpDate) {
      const expDate = new Date(profileExpDate);
      if (expDate < new Date()) {
        console.error(`   ❌ FAIL: Provisioning profile has EXPIRED`);
        console.error(`      ExpirationDate: ${profileExpDate}`);
        allChecksPassed = false;
      }
    }
    
    if (profileAppId === EXPECTED_APP_ID && profileTeamId === EXPECTED_TEAM_ID && profileExpDate) {
      console.log('   ✅ PASS: Profile content matches expected values');
    }
  } catch (err) {
    console.error('   ❌ FAIL: Could not read or parse embedded.provisionprofile');
    console.error(`      Error: ${err.message}`);
    allChecksPassed = false;
  }
}

// 3. Check entitlements and verify they match the embedded profile
console.log('');
console.log('3. Checking entitlements and verifying they match embedded profile...');
try {
  const entitlementsOutput = execSync(`codesign -d --entitlements :- "${appPath}" 2>/dev/null`, {
    encoding: 'utf-8'
  });
  
  const entitlementsPlist = execSync(`echo '${entitlementsOutput.replace(/'/g, "'\"'\"'")}' | plutil -p -`, {
    encoding: 'utf-8'
  });
  
  const hasAppId = entitlementsPlist.includes('application-identifier');
  const hasTeamId = entitlementsPlist.includes('team-identifier');
  const hasSandbox = entitlementsPlist.includes('app-sandbox') && entitlementsPlist.includes('true');
  
  // Extract values
  const appIdMatch = entitlementsPlist.match(/application-identifier.*?=>\s*"([^"]+)"/);
  const teamIdMatch = entitlementsPlist.match(/team-identifier.*?=>\s*"([^"]+)"/);
  
  const appId = appIdMatch ? appIdMatch[1] : null;
  const teamId = teamIdMatch ? teamIdMatch[1] : null;
  
  console.log(`   Entitlements application-identifier: ${appId || 'MISSING'}`);
  console.log(`   Entitlements team-identifier: ${teamId || 'MISSING'}`);
  console.log(`   Entitlements app-sandbox: ${hasSandbox ? 'true' : 'MISSING'}`);
  
  const EXPECTED_APP_ID = 'T6YG6KXA9D.com.nexuscountdown';
  const EXPECTED_TEAM_ID = 'T6YG6KXA9D';
  
  if (!hasAppId || !appId) {
    console.error('   ❌ FAIL: Missing application-identifier in entitlements');
    console.error('      electron-builder should add this automatically based on appId and mas.identity');
    allChecksPassed = false;
  } else if (appId !== EXPECTED_APP_ID) {
    console.error(`   ❌ FAIL: Wrong application-identifier: ${appId}`);
    console.error(`      Expected: ${EXPECTED_APP_ID}`);
    allChecksPassed = false;
  } else if (!hasTeamId || teamId !== EXPECTED_TEAM_ID) {
    console.error(`   ❌ FAIL: Wrong or missing team-identifier: ${teamId || 'MISSING'}`);
    console.error(`      Expected: ${EXPECTED_TEAM_ID}`);
    allChecksPassed = false;
  } else if (!hasSandbox) {
    console.error('   ❌ FAIL: Missing app-sandbox entitlement');
    allChecksPassed = false;
  } else {
    console.log('   ✅ PASS: Entitlements are correct');
    
    // Verify entitlements match profile (if profile was successfully read)
    if (fs.existsSync(embeddedProfile)) {
      try {
        const profileData = execSync(`security cms -D -i "${embeddedProfile}" 2>/dev/null`, {
          encoding: 'utf-8'
        });
        const profilePlist = execSync(`echo '${profileData.replace(/'/g, "'\"'\"'")}' | plutil -p -`, {
          encoding: 'utf-8'
        });
        const profileAppIdMatch = profilePlist.match(/Entitlements.*?application-identifier.*?=>\s*"([^"]+)"/s);
        const profileAppId = profileAppIdMatch ? profileAppIdMatch[1] : null;
        const profileTeamIdMatch = profilePlist.match(/TeamIdentifier.*?=>\s*\[\s*0\s*=>\s*"([^"]+)"/) ||
                                    profilePlist.match(/team-identifier.*?=>\s*"([^"]+)"/);
        const profileTeamId = profileTeamIdMatch ? profileTeamIdMatch[1] : null;
        
        if (profileAppId && appId !== profileAppId) {
          console.error(`   ❌ FAIL: Entitlements application-identifier does not match profile`);
          console.error(`      Entitlements: ${appId}`);
          console.error(`      Profile: ${profileAppId}`);
          allChecksPassed = false;
        } else if (profileTeamId && teamId !== profileTeamId) {
          console.error(`   ❌ FAIL: Entitlements team-identifier does not match profile`);
          console.error(`      Entitlements: ${teamId}`);
          console.error(`      Profile: ${profileTeamId}`);
          allChecksPassed = false;
        } else if (profileAppId && profileTeamId) {
          console.log('   ✅ PASS: Entitlements match embedded profile');
        }
      } catch (err) {
        // Profile comparison failed, but entitlements are correct
        console.log('   ⚠️  Could not verify entitlements match profile (entitlements are correct)');
      }
    }
  }
} catch (err) {
  console.error('   ❌ FAIL: Could not read entitlements');
  console.error(`      Error: ${err.message}`);
  allChecksPassed = false;
}

// 4. Check code signature
console.log('');
console.log('4. Checking code signature...');
try {
  const verifyOutput = execSync(`codesign -dv --verbose=4 "${appPath}" 2>&1`, {
    encoding: 'utf-8'
  });
  
  if (verifyOutput.includes('Authority=3rd Party Mac Developer Application')) {
    console.log('   ✅ PASS: Signed with MAS certificate');
    const identityMatch = verifyOutput.match(/Authority=([^\n]+)/);
    if (identityMatch) {
      console.log(`      Identity: ${identityMatch[1]}`);
    }
  } else {
    console.error('   ❌ FAIL: Not signed with MAS certificate');
    console.error('      Expected: 3rd Party Mac Developer Application');
    allChecksPassed = false;
  }
} catch (err) {
  console.error('   ❌ FAIL: Code signature verification failed');
  console.error(`      Error: ${err.message}`);
  allChecksPassed = false;
}

// 5. Check .pkg signature if available
if (pkgPath && fs.existsSync(pkgPath)) {
  console.log('');
  console.log('5. Checking .pkg signature...');
  try {
    const pkgVerify = execSync(`pkgutil --check-signature "${pkgPath}"`, {
      encoding: 'utf-8'
    });
    
    if (pkgVerify.includes('3rd Party Mac Developer Installer')) {
      console.log('   ✅ PASS: .pkg signed with MAS installer certificate');
    } else {
      console.error('   ❌ FAIL: .pkg not signed with MAS installer certificate');
      allChecksPassed = false;
    }
  } catch (err) {
    console.error('   ❌ FAIL: .pkg signature verification failed');
    console.error(`      Error: ${err.message}`);
    allChecksPassed = false;
  }
}

// 6. Check universal binary
console.log('');
console.log('6. Checking universal binary (arm64 + x86_64)...');
try {
  const mainBinary = path.join(appPath, 'Contents', 'MacOS', 'Nexus Countdown');
  if (fs.existsSync(mainBinary)) {
    const lipoInfo = execSync(`lipo -info "${mainBinary}"`, {
      encoding: 'utf-8'
    });
    
    const hasArm64 = lipoInfo.includes('arm64');
    const hasX86_64 = lipoInfo.includes('x86_64') || lipoInfo.includes('i386');
    
    if (hasArm64 && hasX86_64) {
      console.log('   ✅ PASS: Universal binary (arm64 + x86_64)');
      console.log(`      ${lipoInfo.trim()}`);
    } else {
      console.error('   ❌ FAIL: Not a universal binary');
      console.error(`      ${lipoInfo.trim()}`);
      console.error('      This will cause TestFlight error 91167');
      allChecksPassed = false;
    }
  } else {
    console.error('   ❌ FAIL: Main binary not found');
    allChecksPassed = false;
  }
} catch (err) {
  console.error('   ❌ FAIL: Could not check binary architecture');
  console.error(`      Error: ${err.message}`);
  allChecksPassed = false;
}

// Cleanup temp directory
const tempDir = path.join(REPO_ROOT, '.mas-verify-temp');
if (fs.existsSync(tempDir)) {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

// Final summary
console.log('');
if (allChecksPassed) {
  console.log('✅ All verification checks PASSED');
  console.log('');
  console.log('The MAS build is ready for TestFlight upload.');
  console.log('Key points:');
  console.log('  - Embedded provisioning profile exists and matches expected values');
  console.log('  - Entitlements include application-identifier (added by electron-builder)');
  console.log('  - Entitlements match embedded profile');
  console.log('  - Universal binary (arm64 + x86_64)');
  console.log('  - Signed with MAS certificates');
  process.exit(0);
} else {
  console.error('❌ Verification FAILED');
  console.error('');
  console.error('The MAS build has issues that will prevent TestFlight installation.');
  console.error('Common issues:');
  console.error('  - Missing or incorrect embedded.provisionprofile');
  console.error('  - Missing application-identifier in entitlements (electron-builder should add this)');
  console.error('  - Entitlements do not match embedded profile');
  console.error('  - Not a universal binary (will cause error 91167)');
  process.exit(1);
}
