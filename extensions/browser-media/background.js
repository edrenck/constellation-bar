// No host_permissions: a toolbar click grants access to just this tab.
const ports = new Map();
const enabled = new Set();
async function identity() {
  const stored = await chrome.storage.local.get("installationID");
  if (stored.installationID) return stored.installationID;
  const installationID = crypto.randomUUID();
  await chrome.storage.local.set({ installationID });
  return installationID;
}
chrome.action.onClicked.addListener(async tab => {
  if (!tab.id || !/^https?:/.test(tab.url || "")) return;
  try {
    if (enabled.has(tab.id)) {
      await chrome.tabs.sendMessage(tab.id, { type: "stop" });
      enabled.delete(tab.id); ports.get(tab.id)?.disconnect(); ports.delete(tab.id);
      await chrome.action.setBadgeText({ tabId: tab.id, text: "" });
    } else {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
      enabled.add(tab.id);
      await chrome.action.setBadgeText({ tabId: tab.id, text: "ON" });
      await chrome.action.setTitle({ tabId: tab.id, title: "Sharing this tab with ConstellationBar. Click to stop." });
    }
  } catch (error) {
    await chrome.action.setBadgeText({ tabId: tab.id, text: "!" });
    await chrome.action.setTitle({ tabId: tab.id, title: "Could not enable this page: " + error.message });
  }
});
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message.type !== "snapshot" || !sender.tab || sender.frameId !== 0) return;
  const tabId = sender.tab.id;
  // Only content scripts injected by the user's toolbar action can send internal messages.
  // Page scripts have no runtime API and externally_connectable is intentionally absent.
  (async () => {
    let port = ports.get(tabId);
    if (!port) {
      port = chrome.runtime.connectNative("dev.constellation.browser_media");
      ports.set(tabId, port);
      port.onMessage.addListener(command => {
        if (command) chrome.tabs.sendMessage(tabId, { type: "command", command }).catch(() => {});
      });
      port.onDisconnect.addListener(() => {
        const error = chrome.runtime.lastError;
        ports.delete(tabId);
        if (error) {
          chrome.action.setBadgeText({ tabId, text: "!" }).catch(() => {});
          chrome.action.setTitle({ tabId, title: "Install the native bridge. See the extension README. " + error.message }).catch(() => {});
        }
      });
    }
    const id = (await identity()) + "-" + tabId;
    port.postMessage({ ...message.state, id, timestamp: Date.now() / 1000 });
    respond({ ok: true });
  })().catch(error => respond({ error: error.message }));
  return true;
});
chrome.tabs.onRemoved.addListener(tabId => { ports.get(tabId)?.disconnect(); ports.delete(tabId); enabled.delete(tabId); });
chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status !== "loading") return;
  ports.get(tabId)?.disconnect(); ports.delete(tabId); enabled.delete(tabId);
  chrome.action.setBadgeText({ tabId, text: "" }).catch(() => {});
});
