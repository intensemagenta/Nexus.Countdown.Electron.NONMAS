# Nexus Countdown Electron

A minimal Electron app wrapper for the Nexus Countdown UI.

## Development

1. Install dependencies:
   ```bash
   npm install
   ```

2. Run in development mode:
   ```bash
   npm run dev
   ```

This will open the Electron window with DevTools enabled.

## Building

To build a macOS `.app` and `.dmg`:

```bash
npm run build:mac
```

This creates:
- `dist/mac/Nexus Countdown (Electron).app` - The application bundle
- `dist/*.dmg` - A DMG installer (unsigned for local testing)

## Verification

After building, verify the bundle:

```bash
npm run verify:electron:bundle
```

## File Structure

- `electron/main.js` - Electron main process
- `electron/preload.js` - Preload script for safe API exposure
- `web/index.html` - UI (copied from root `index.html`, SHA256 verified identical)
- `build/icon.icns` - Application icon (placeholder)
- `electron-builder.yml` - Build configuration

## Notes

- The `web/index.html` file is byte-for-byte identical to the root `index.html` (SHA256: `e59f81dd660e0741032e0e3daf2a475bad5aa215b4b256c3f480e4fcfbf133a7`)
- Signing and Mac App Store (MAS) packaging are not configured yet
- Default window size: 900 x 700 pixels
- Security defaults: `contextIsolation: true`, `nodeIntegration: false`, `enableRemoteModule: false`

