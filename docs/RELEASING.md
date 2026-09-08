# Releasing ConstellationBar

Development builds are ad-hoc signed. They are CI artifacts, not public distribution downloads. The signed-release workflow fails without distribution credentials and creates only a draft.

## Local signed build

Use Xcode 26.1 or later with its macOS SDK. Before building, accept Xcode's license and install a **Developer ID Application** certificate with its private key through Xcode Settings → Accounts → Manage Certificates. An Apple Development certificate is not a replacement.

### First-time local notarization setup

1. Open Xcode and complete its license agreement and first-launch components. If command-line builds still report a license error, run `sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license` in your own terminal to read and accept it. Do not bypass this step.
2. In your [Apple Account](https://account.apple.com/), generate an app-specific password under Sign-In and Security → App-Specific Passwords. Two-factor authentication is required; see [Apple's instructions](https://support.apple.com/en-gb/102654).
3. Double-click `scripts/setup-notarization.command` in Finder, or run `./scripts/setup-notarization.sh` from your own terminal. Enter your Apple Developer account email and the Team ID matching your Developer ID certificate. When exactly one Developer ID team is installed, the helper offers that ID as the default.
4. Enter the app-specific password at notarytool's secure prompt. The helper validates it with Apple and stores it in the local Keychain as `constellation-release`. Do not enter it in chat, commit it, or pass it on a shell command line.

Set `DEVELOPER_DIR` to your installed Xcode's `Contents/Developer` if Command Line Tools are selected. This does not change the global selected toolchain. The release script checks the Keychain profile before building, requires Apple's explicit Accepted status, and retains Apple's JSON response/log under ignored `.build/notarization-report.*` directories for troubleshooting. An unsuccessful run does not replace distribution files from a previous successful run; always identify an artifact by the successful run and checksum.

Then:


```sh
swift test
CONSTELLATION_UI_TESTS=1 swift test
node --test extensions/browser-media/content.test.cjs
CONSTELLATION_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
CONSTELLATION_NOTARY_PROFILE='YOUR_PROFILE' ./scripts/release.sh
```

The script builds both architectures, signs with Hardened Runtime and a timestamp, submits to Apple, waits for approval, staples and validates the ticket, and assesses the app with Gatekeeper. It creates `.build/distribution/ConstellationBar-VERSION-universal.zip` and `SHA256SUMS` only after those checks succeed. The final ZIP includes the stapled ticket.

## GitHub Actions

The canonical source and release repository is [edrenck/constellation-bar](https://github.com/edrenck/constellation-bar). `main` is the integration branch. Build and test selects Xcode 26.1.1 on macOS 15, from the [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md); it tests and archives a development build. CI does not establish the complete supported hardware/OS matrix.

Configure the `distribution` environment in GitHub, with approval rules appropriate for the repository. Add these **environment secrets** through GitHub Settings, never in source files or an issue:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded exported Developer ID certificate and private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password used to encrypt the export |
| `NOTARY_KEY_BASE64` | Base64-encoded App Store Connect API private key authorized for notarization |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | API issuer ID |

Set environment **variable** `DEVELOPER_ID_IDENTITY` to the exact `Developer ID Application: … (TEAMID)` identity. The workflow imports the certificate into a temporary keychain and removes credentials on completion. Signing is never run for pull requests.

1. Update `VERSION` (numeric `major.minor.patch`) and increment the build number in `Resources/Info.plist`. Build scripts embed the source commit too.
2. Merge the tested release commit. Create and push its matching `vVERSION` tag.
3. Run **Signed release draft** manually with that existing tag. It checks the tag and version, tests, signs, notarizes and uploads verified files to a draft. It never falls back to ad-hoc signing.
4. Complete the clean-install and hardware checks in `CONTRIBUTING.md` using the downloaded final ZIP on another Mac. Verify the checksum, About version/commit, permissions, launch at login, upgrade and uninstall. Record actual OS/CPU coverage in release notes.
5. Publish the draft only after those checks pass. Published releases in a public repository are available without authentication; drafts remain unpublished. Verify anonymous download access before linking the website.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Do not ask users to disable Gatekeeper. Automatic updates and a Homebrew cask remain follow-ups after a stable public download location is chosen.
