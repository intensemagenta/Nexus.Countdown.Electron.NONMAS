const { app, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');

// Keep a global reference of the window object
let mainWindow;

function createWindow() {
  // Create the browser window
  mainWindow = new BrowserWindow({
    width: 900,
    height: 700,
    resizable: true,
    title: 'Nexus Countdown',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      enableRemoteModule: false,
      sandbox: true,
      preload: path.join(__dirname, 'preload.js')
    }
  });

  // Determine the path to index.html
  // In development: load from ../../web/index.html
  // In production: load from the bundled copy in app.asar
  let htmlPath;
  
  if (process.env.NODE_ENV === 'development' || !app.isPackaged) {
    // Development: load from repo root web directory
    htmlPath = path.join(__dirname, '..', '..', 'web', 'index.html');
  } else {
    // Production: load from app bundle
    // electron-builder packages files into Resources/app.asar/web/index.html
    // app.getAppPath() returns the path to the app.asar or extracted app directory
    htmlPath = path.join(app.getAppPath(), 'web', 'index.html');
  }

  // Load the HTML file
  mainWindow.loadFile(htmlPath).catch(err => {
    console.error('Failed to load index.html:', err);
    console.error('Attempted path:', htmlPath);
  });

  // Open DevTools in development mode
  if (process.env.NODE_ENV !== 'production' && !app.isPackaged) {
    mainWindow.webContents.openDevTools();
  }

  // Emitted when the window is closed
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// This method will be called when Electron has finished initialization
app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    // On macOS, re-create a window when the dock icon is clicked and no other windows are open
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

// Quit when all windows are closed, except on macOS
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

