# Releasing ConstellationBar

1. Update `VERSION` and the bundle build number in `Resources/Info.plist`.
2. Run `swift test` and `./scripts/build-app.sh --universal`.
3. Verify `lipo -info .build/ConstellationBar.app/Contents/MacOS/ConstellationBar` lists arm64 and x86_64.
4. Complete the hardware checks in `CONTRIBUTING.md` and test first launch with a clean config.
5. For public downloads, build with a Developer ID Application identity and notarize using your Apple developer account.
6. Tag the version. The GitHub workflow creates an ad-hoc-signed **draft** ZIP and checksum. Replace it with the signed/notarized archive before publishing a normal public download.

The repository cannot supply a Developer ID certificate, Apple account credentials, or notarization approval. No signing secrets are stored here. The default release workflow is intentionally useful without them, but its output is not a notarized public release.

With an installed signing identity and a configured notarytool keychain profile:

```sh
CONSTELLATION_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./scripts/build-app.sh --universal
ditto -c -k --sequesterRsrc --keepParent .build/ConstellationBar.app .build/ConstellationBar.zip
xcrun notarytool submit .build/ConstellationBar.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple .build/ConstellationBar.app
codesign --verify --deep --strict .build/ConstellationBar.app
spctl --assess --type execute --verbose .build/ConstellationBar.app
# Recreate the ZIP after stapling so it contains the ticket.
ditto -c -k --sequesterRsrc --keepParent .build/ConstellationBar.app .build/ConstellationBar.zip
shasum -a 256 .build/ConstellationBar.zip
```

Check [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for your account/toolchain's requirements. Do not advise users to disable system-wide security settings.

A Homebrew cask and automatic update feed should follow a stable published download URL and a chosen repository owner. Neither is configured with placeholder URLs in this project.
