# Browser media

The first browser provider supports HTML video/audio playback in Chrome, Edge and Brave, including YouTube's main page player. It supports session selection, play/pause and seeking where the page allows it. Queues, previous/next, cross-origin iframe players, Safari and Firefox are not included in this release. Spotify's native app integration is coming later.

## Install

1. Build ConstellationBar with `./scripts/build-app.sh` and keep the app at a stable location.
2. Open your browser's extensions page, enable Developer mode, choose **Load unpacked**, and select this `extensions/browser-media` folder.
3. Copy the extension ID. From the project root, run `python3 scripts/install-browser-bridge.py EXTENSION_ID --browser chrome`. Use `edge` or `brave` as appropriate. Add `--app /path/to/ConstellationBar.app` if you moved the app.
4. Enable **Now Playing** in ConstellationBar and **Browser media** under Connections.
5. Open a video/audio tab and click the extension's toolbar button. Its badge reads **ON**. Click again to stop sharing. Re-enable after page navigation. An **!** badge indicates a setup error; hover the toolbar button for details.

No administrator access, account login, localhost server or broad website permission is needed. Browser `activeTab` permission is granted by the toolbar click. Only the enabled tab's title, playback state, duration and position are passed to the local app. No page content, cookies or browsing history is shared. A paused tab continues to appear until disabled or closed. Local snapshots expire from the app after eight seconds without updates and are cleaned up after one day. The provider sends only play/pause and seek commands.

The extension and native host are experimental developer-installable components, not browser-store releases. A site's playback policies can reject actions; the panel reports these failures. Registration must be repeated if the app path or extension ID changes.

## Remove

Remove the browser extension and `~/Library/Application Support/<browser folder>/NativeMessagingHosts/dev.constellation.browser_media.json`. Local bridge files live under `~/Library/Application Support/ConstellationBar/BrowserMedia` and may then be removed.

## Extension protocol

The native host launches the application executable with `--browser-host`, before AppKit starts. Each JSON message has a native-endian 32-bit length prefix. Snapshots are validated and stored atomically with user-only permissions. Commands have unique IDs, expire after ten seconds, and must be acknowledged before the app reports success. No arbitrary JavaScript or executable commands cross this boundary.

Reference: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
