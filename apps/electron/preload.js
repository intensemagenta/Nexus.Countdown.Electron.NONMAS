const { contextBridge } = require('electron');

// Expose minimal safe environment info to the renderer
contextBridge.exposeInMainWorld('electronEnv', {
  env: process.env.NODE_ENV ?? 'production'
});

