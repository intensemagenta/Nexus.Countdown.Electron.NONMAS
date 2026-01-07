# Provisioning Profile Setup

For Mac App Store submission and TestFlight, you need a Mac App Store provisioning profile.

## Steps to Get Provisioning Profile:

1. **Go to Apple Developer Portal:**
   - Visit: https://developer.apple.com/account/resources/profiles/list
   - Sign in with your Apple Developer account

2. **Create Mac App Store Provisioning Profile:**
   - Click the "+" button to create a new profile
   - Select **"Mac App Store"** under Distribution
   - Select your App ID: `com.nexuscountdown`
   - Select your **"3rd Party Mac Developer Application"** certificate
   - Name it (e.g., "Nexus Countdown Mac App Store")
   - Click "Generate"

3. **Download and Place Profile:**
   - Download the `.provisionprofile` file
   - Rename it to `embedded.provisionprofile`
   - Place it in this directory: `cert/embedded.provisionprofile`

4. **Rebuild:**
   - Run `./scripts/build.sh` again
   - The provisioning profile will be automatically embedded in the app bundle

## Alternative: Manual Embedding

If you already have a provisioning profile:

```bash
# Copy to cert folder
cp /path/to/your/profile.provisionprofile cert/embedded.provisionprofile

# Or manually embed after build:
cp cert/embedded.provisionprofile "src-tauri/target/universal-apple-darwin/release/bundle/macos/Nexus Countdown.app/Contents/embedded.provisionprofile"

# Then re-sign:
codesign --force --deep --sign "3rd Party Mac Developer Application: Adam Parsons (T6YG6KXA9D)" \
  --entitlements "src-tauri/entitlements.plist" \
  --options runtime \
  "src-tauri/target/universal-apple-darwin/release/bundle/macos/Nexus Countdown.app"
```
