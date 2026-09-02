'use strict';

const HOST_NAME = 'com.wavern.browserbridge';
let port = null;

function connect() {
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
    port.onDisconnect.addListener(() => {
      port = null;
      setTimeout(connect, 5000);
    });
  } catch (e) {
    port = null;
  }
}

function sendAudibleTabs() {
  if (!port) return;
  chrome.tabs.query({ audible: true }, (tabs) => {
    if (chrome.runtime.lastError || !port) return;
    const payload = {
      tabs: tabs.map(t => ({
        title: t.title || '',
        url: t.url || '',
        favIconUrl: t.favIconUrl || null,
        audible: t.audible || false
      }))
    };
    try { port.postMessage(payload); } catch (_) {}
  });
}

connect();
setInterval(sendAudibleTabs, 2000);
chrome.tabs.onUpdated.addListener((_id, change) => {
  if (change.audible !== undefined) sendAudibleTabs();
});
chrome.tabs.onRemoved.addListener(sendAudibleTabs);
