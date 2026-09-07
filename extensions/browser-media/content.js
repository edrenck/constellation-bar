(() => {
  // Injection is idempotent, and sharing ends on navigation or a second toolbar click.
  if (globalThis.__constellationMediaStop) globalThis.__constellationMediaStop();
  let acknowledged = null, error = null, processing = false;
  function media() {
    const elements = [...document.querySelectorAll("video,audio")];
    return elements.find(element => !element.paused && !element.ended) || elements.find(element => element.readyState > 0);
  }
  async function report() {
    const element = media();
    if (!element) return;
    const duration = Number.isFinite(element.duration) ? Math.max(0, element.duration) : 0;
    try {
      await chrome.runtime.sendMessage({ type: "snapshot", state: {
        title: document.title.slice(0, 1000), playing: !element.paused && !element.ended,
        position: Number.isFinite(element.currentTime) ? Math.max(0, element.currentTime) : 0,
        duration, canSeek: duration > 0 && element.seekable.length > 0,
        acknowledged, error
      }});
    } catch { /* The toolbar badge explains bridge failures. */ }
  }
  async function listener(message) {
    if (message.type === "stop") { stop(); return; }
    if (message.type !== "command" || processing) return;
    const command = message.command;
    if (!command || command.id === acknowledged) return;
    processing = true;
    try {
      const element = media();
      if (!element) throw new Error("This tab no longer has playable media.");
      if (Date.now() / 1000 - command.timestamp > 10) throw new Error("Playback command expired.");
      if (command.action === "playPause") {
        if (element.paused) await element.play(); else element.pause();
      } else if (command.action === "seek" && Number.isFinite(command.position) && Number.isFinite(element.duration) && element.seekable.length) {
        element.currentTime = Math.max(0, Math.min(element.duration, command.position));
      } else throw new Error("This playback action is not supported.");
      error = null;
    } catch (failure) { error = failure.message; }
    acknowledged = command.id; processing = false; await report();
  }
  const timer = setInterval(report, 1000);
  function stop() { clearInterval(timer); chrome.runtime.onMessage.removeListener(listener); delete globalThis.__constellationMediaStop; }
  globalThis.__constellationMediaStop = stop;
  chrome.runtime.onMessage.addListener(listener);
  report();
})();
