'use strict';

const HOST_NAME = 'com.wavern.browserbridge';
let port = null;
// tabId -> volume (0..1). Kept so we can re-apply after navigations.
let tabVolumes = {};

function connect() {
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
    port.onMessage.addListener(onHostMessage);
    port.onDisconnect.addListener(() => {
      port = null;
      setTimeout(connect, 5000);
    });
  } catch (e) {
    port = null;
  }
}

function onHostMessage(msg) {
  if (!msg || typeof msg.volumes !== 'object') return;
  const next = {};
  for (const [id, v] of Object.entries(msg.volumes)) {
    const tabId = Number(id);
    const vol = Math.min(Math.max(Number(v), 0), 1);
    if (!Number.isFinite(tabId) || !Number.isFinite(vol)) continue;
    next[tabId] = vol;
    if (tabVolumes[tabId] !== vol) applyVolume(tabId, vol);
  }
  // Tabs dropped from the map go back to full volume.
  for (const id of Object.keys(tabVolumes)) {
    if (!(id in next)) applyVolume(Number(id), 1);
  }
  tabVolumes = next;
}

// Runs inside the page: set every media element's volume and keep new ones in line.
function pageApplyVolume(v) {
  const apply = () => document.querySelectorAll('audio, video').forEach(el => { el.volume = v; });
  apply();
  window.__wavernVolume = v;
  if (!window.__wavernObserver) {
    window.__wavernObserver = new MutationObserver(() => {
      const wv = window.__wavernVolume;
      if (wv === undefined) return;
      document.querySelectorAll('audio, video').forEach(el => { if (el.volume !== wv) el.volume = wv; });
    });
    window.__wavernObserver.observe(document.documentElement, { childList: true, subtree: true });
  }
}

function applyVolume(tabId, volume) {
  chrome.scripting.executeScript({
    target: { tabId, allFrames: true },
    func: pageApplyVolume,
    args: [volume]
  }).catch(() => {});
}

function sendAudibleTabs() {
  if (!port) return;
  chrome.tabs.query({ audible: true }, (tabs) => {
    if (chrome.runtime.lastError || !port) return;
    const payload = {
      tabs: tabs.map(t => ({
        id: t.id,
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
chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.audible !== undefined) sendAudibleTabs();
  // Page (re)loaded or started playing: the injected observer is gone, re-apply.
  if ((change.status === 'complete' || change.audible === true) && tabId in tabVolumes) {
    applyVolume(tabId, tabVolumes[tabId]);
  }
});
chrome.tabs.onRemoved.addListener((tabId) => {
  delete tabVolumes[tabId];
  sendAudibleTabs();
});
