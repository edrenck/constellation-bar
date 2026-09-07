# Releasing ConstellationBar

Development builds are ad-hoc signed. They are CI artifacts, not public distribution downloads. The signed-release workflow fails without distribution credentials and creates only a draft.

## Local signed build

Use Xcode 26.1 or later with its macOS SDK. Before building, accept Xcode's license and install a **Developer ID Application** certificate with its private key through Xcode Settings → Accounts → Manage Certificates. An Apple Development certificate is not a replacement.

Create a `notarytool` keychain profile using your Apple account's supported credentials. Do not put credentials in this repository. Then:

```sh
swift test
CONSTELLATION_UI_TESTS=1 swift test
node --test extensions/browser-media/content.test.cjs
CONSTELLATION_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
CONSTELLATION_NOTARY_PROFILE='YOUR_PROFILE' ./scripts/release.sh
```

The script builds both architectures, signs with Hardened Runtime and a timestamp, submits to Apple, waits for approval, staples and validates the ticket, and assesses the app with Gatekeeper. It creates `.build/distribution/ConstellationBar-VERSION-universal.zip` and `SHA256SUMS` only after those checks succeed. The final ZIP includes the stapled ticket.

## GitHub Actions

The canonical repository is private [edrenck/constellation-bar](https://github.com/edrenck/constellation-bar). `main` is the integration branch. Build and test selects Xcode 26.1.1 on macOS 15, from the [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md); it tests and archives a development build. CI does not establish the complete supported hardware/OS matrix.

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
5. Publish the draft only after those checks pass. A private repository's release downloads require authentication; making releases generally available needs a separate distribution decision.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Do not ask users to disable Gatekeeper. Automatic updates and a Homebrew cask remain follow-ups after a stable public download location is chosen.
