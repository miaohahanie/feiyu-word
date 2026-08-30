const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('petAPI', {
  getClipboard: () => ipcRenderer.invoke('get-clipboard'),
  loadData: () => ipcRenderer.invoke('load-data'),
  saveData: (data) => ipcRenderer.invoke('save-data', data),
  hideWindow: () => ipcRenderer.invoke('window-hide'),
  setWindowMode: (mode) => ipcRenderer.invoke('set-window-mode', mode),
  getWindowPosition: () => ipcRenderer.invoke('get-window-position'),
  setWindowPosition: (x, y) => ipcRenderer.invoke('set-window-position', x, y),
  beginWindowDrag: () => ipcRenderer.invoke('begin-window-drag'),
  endWindowDrag: () => ipcRenderer.invoke('end-window-drag'),
  getAutoLaunch: () => ipcRenderer.invoke('get-auto-launch'),
  setAutoLaunch: (enabled) => ipcRenderer.invoke('set-auto-launch', enabled),
  lookupOnline: (word) => ipcRenderer.invoke('lookup-online', word),
  translateText: (text) => ipcRenderer.invoke('translate-text', text),
  onShortcut: (callback) => ipcRenderer.on('shortcut-summon', callback),
  onShortcutHide: (callback) => ipcRenderer.on('shortcut-hide-panel', callback),
  onPetShown: (callback) => ipcRenderer.on('pet-shown', callback)
});
