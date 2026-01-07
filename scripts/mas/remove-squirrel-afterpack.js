const fs = require('fs');
const path = require('path');

/**
 * afterPack hook for electron-builder
 * Removes Squirrel.framework and ShipIt from MAS builds before electron-builder signs
 * This runs after electron-builder packs the app but before it signs
 */
exports.default = async function(context) {
  const appPath = context.appOutDir;
  const appName = context.packager.appInfo.productFilename;
  const appBundle = path.join(appPath, `${appName}.app`);
  
  if (!fs.existsSync(appBundle)) {
    console.log('⚠️  App bundle not found, skipping Squirrel removal');
    return;
  }
  
  console.log('🗑️  Removing Squirrel.framework and ShipIt from MAS build...');
  
  const squirrelFramework = path.join(appBundle, 'Contents', 'Frameworks', 'Squirrel.framework');
  if (fs.existsSync(squirrelFramework)) {
    console.log('   Removing Squirrel.framework...');
    fs.rmSync(squirrelFramework, { recursive: true, force: true });
    console.log('   ✅ Removed Squirrel.framework');
  }
  
  // Also remove ShipIt if it exists elsewhere
  const shipItPath = path.join(squirrelFramework, 'Versions', 'A', 'Resources', 'ShipIt');
  if (fs.existsSync(shipItPath)) {
    console.log('   Removing ShipIt binary...');
    fs.unlinkSync(shipItPath);
    console.log('   ✅ Removed ShipIt');
  }
  
  console.log('✅ Squirrel removal complete');
};


