#!/usr/bin/env node
/**
 * Finds and validates the provisioning profile for the Electron MAS app
 * Prints absolute path to profile if valid, fails otherwise
 */

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '../..');
const APP_ID = 'com.nexuscountdown';
const TEAM_ID = 'T6YG6KXA9D';
const EXPECTED_APP_IDENTIFIER = `${TEAM_ID}.${APP_ID}`;

// Search locations for provisioning profile
// IMPORTANT: Only use Nexus_Countdown.provisionprofile - never use embedded.provisionprofile
// The embedded.provisionprofile in the app bundle is created from this source file during build
const PROFILE_SEARCH_PATHS = [
  path.join(REPO_ROOT, 'cert', 'Nexus_Countdown.provisionprofile'),
];

let profilePath = null;

// Try exact matches first
for (const profilePattern of PROFILE_SEARCH_PATHS) {
  if (profilePattern.includes('*')) {
    // Handle glob pattern
    try {
      const result = execSync(
        `find "${path.dirname(profilePattern)}" -name "${path.basename(profilePattern)}" -type f 2>/dev/null | head -1`,
        { encoding: 'utf-8' }
      );
      const found = result.trim();
      if (found && fs.existsSync(found)) {
        profilePath = found;
        break;
      }
    } catch (err) {
      // Continue searching
    }
  } else if (fs.existsSync(profilePattern)) {
    profilePath = profilePattern;
    break;
  }
}

if (!profilePath) {
  console.error(`❌ ERROR: Provisioning profile not found`);
  console.error(`   Searched in: ${path.join(REPO_ROOT, 'cert')}`);
  console.error(`   Expected file: Nexus_Countdown.provisionprofile`);
  console.error(`   Note: Do not use embedded.provisionprofile - it is created from the source file during build`);
  process.exit(1);
}

// Validate the profile
try {
  // Decode the provisioning profile
  const profileData = execSync(
    `security cms -D -i "${profilePath}" 2>/dev/null`,
    { encoding: 'utf-8' }
  );
  
  // Parse plist
  const plistData = execSync(
    `echo '${profileData.replace(/'/g, "'\"'\"'")}' | plutil -p -`,
    { encoding: 'utf-8' }
  );
  
  // Extract application identifier from entitlements
  const appIdMatch = plistData.match(/Entitlements.*?application-identifier.*?=>\s*"([^"]+)"/s);
  if (!appIdMatch) {
    console.error(`❌ ERROR: Could not parse application-identifier from profile`);
    console.error(`   Profile: ${profilePath}`);
    process.exit(1);
  }
  
  const profileAppId = appIdMatch[1];
  
  if (profileAppId !== EXPECTED_APP_IDENTIFIER) {
    console.error(`❌ ERROR: Provisioning profile application-identifier mismatch`);
    console.error(`   Expected: ${EXPECTED_APP_IDENTIFIER}`);
    console.error(`   Found:    ${profileAppId}`);
    console.error(`   Profile:  ${profilePath}`);
    console.error(`   Note: Profile must match app bundle ID: ${APP_ID}`);
    process.exit(1);
  }
  
  // Extract team identifier
  const teamIdMatch = plistData.match(/TeamIdentifier.*?=>\s*\[\s*0\s*=>\s*"([^"]+)"/) ||
                      plistData.match(/team-identifier.*?=>\s*"([^"]+)"/);
  const profileTeamId = teamIdMatch ? teamIdMatch[1] : null;
  
  if (profileTeamId && profileTeamId !== TEAM_ID) {
    console.error(`❌ ERROR: Provisioning profile team-identifier mismatch`);
    console.error(`   Expected: ${TEAM_ID}`);
    console.error(`   Found:    ${profileTeamId}`);
    console.error(`   Profile:  ${profilePath}`);
    process.exit(1);
  }
  
  // Profile is valid
  console.log(path.resolve(profilePath));
  
} catch (err) {
  console.error(`❌ ERROR: Failed to validate provisioning profile`);
  console.error(`   Profile: ${profilePath}`);
  console.error(`   Error: ${err.message}`);
  process.exit(1);
}

