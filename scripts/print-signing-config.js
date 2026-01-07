#!/usr/bin/env node

// Print electron-builder signing configuration for debugging

const path = require('path');
const fs = require('fs');

const configPath = path.join(__dirname, '..', 'apps', 'electron', 'package.json');

if (!fs.existsSync(configPath)) {
  console.error('Error: Could not find config at:', configPath);
  process.exit(1);
}

const pkg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const buildConfig = pkg.build || {};

console.log('=== Electron Builder Signing Configuration ===');
console.log('appId:', buildConfig.appId);
console.log('productName:', buildConfig.productName);
console.log('');
console.log('mac.identity:', buildConfig.mac?.identity || '(not set)');
console.log('mac.forceCodeSigning:', buildConfig.mac?.forceCodeSigning || '(not set)');
console.log('');
console.log('mas.identity:', buildConfig.mas?.identity || '(not set)');
console.log('mas.electronTeamID:', '(set via ELECTRON_TEAM_ID env var in build script)');
console.log('');

// Expected values (electron-builder uses just the name, not the full cert name)
const expectedIdentity = "Adam Parsons (T6YG6KXA9D)";
const expectedTeamID = "T6YG6KXA9D";

let allGood = true;

if (buildConfig.mas?.identity !== expectedIdentity) {
  console.log('❌ mas.identity does not match expected value');
  allGood = false;
}

if (buildConfig.mac?.identity !== expectedIdentity) {
  console.log('⚠️  mac.identity does not match expected value (may be OK if using env vars)');
}

if (allGood && buildConfig.mas?.identity === expectedIdentity) {
  console.log('✅ Configuration looks correct!');
  console.log('   Team ID is set via ELECTRON_TEAM_ID env var in build script');
}

