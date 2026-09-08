# Third-party notices

ConstellationBar is built with Swift and macOS system frameworks and has no third-party Swift package runtime dependencies. AeroSpace, Apple Music, Tailscale, Codex and browser integrations communicate with separately installed software; that software retains its own licenses. Open-Meteo supplies opt-in weather data and has its own service/data terms.

The website uses React, Vinext, Base UI, shadcn/ui components, Lucide, and other packages recorded with exact versions in `website/package-lock.json`. Vendored component source under `website/components/ui` originates from the Sites starter's shadcn catalog. Its upstream notices are included in `website/COMPONENTS_LICENSE.txt`. These components are not relicensed by the repository's MIT file.

The website build generates `dist/client/THIRD_PARTY_NOTICES.txt` from the license files of dependencies actually included in browser chunks. Distribute that file with the exported site, alongside the HTML, CSS, JavaScript and images. Build tools may have separate licenses; consult the lockfile and each installed package for their terms.

Product preview PNGs are rendered by ConstellationBar using fixture data. macOS system symbols and third-party app names/icons shown inside the previews retain their respective rights; no affiliation or endorsement is implied.
