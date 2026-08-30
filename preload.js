const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('petAPI', {
  getClipboard: () => ipcRenderer.invoke('get-clipboard'),
  loadData: () => ipcRenderer.invoke('load-data'),
  saveData: (data) => ipcRenderer.invoke('save-data', data),
  hideWindow: () => ipcRenderer.invoke('window-hide'),
  setIgnoreMouseEvents: (ignore) => ipcRenderer.invoke('set-ignore-mouse', ignore),
  getAutoLaunch: () => ipcRenderer.invoke('get-auto-launch'),
  setAutoLaunch: (enabled) => ipcRenderer.invoke('set-auto-launch', enabled),
  lookupOnline: (word) => ipcRenderer.invoke('lookup-online', word),
  translateText: (text) => ipcRenderer.invoke('translate-text', text),
  onShortcut: (callback) => ipcRenderer.on('shortcut-summon', callback),
  onShortcutHide: (callback) => ipcRenderer.on('shortcut-hide-panel', callback),
  onPetShown: (callback) => ipcRenderer.on('pet-shown', callback)
});
