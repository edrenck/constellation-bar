# ConstellationBar website

The product website is ordinary source inside this repository. Build it once and upload the resulting files to your subdomain or any static web host. No Sites account, Cloudflare Worker, application server, database, analytics or signup service is required.

## Build

Use Node.js 22.13 or later and npm:

```sh
cd website
npm ci
npm run build
```

The deployable files are written to `dist/client/`: HTML, CSS, JavaScript, images and `THIRD_PARTY_NOTICES.txt`. Source lives in `app/`, `components/`, `public/` and the configuration files here. Generated build output and `node_modules` are ignored by Git. The Website export workflow also supplies a downloadable `constellation-website` artifact.

To edit locally, use `npm run dev`. To check the exported files, use `npm start`, then open `http://127.0.0.1:4173`.

## Host on a subdomain

Point your desired subdomain at your hosting provider and enable HTTPS using its normal instructions. Upload the **contents** of `website/dist/client/` to that subdomain's document root, keeping every asset directory intact. Serve `index.html` as the index document. There is no server process to deploy, no secret environment file and no proprietary hosting configuration.

For example, a host mapping `bar.example.com` to `/var/www/bar` should serve `dist/client/index.html` as `/var/www/bar/index.html`, with the exported asset directories alongside it. Current asset URLs assume the root of a domain/subdomain. A path such as `example.com/bar/` needs a separately configured base path and is not the current target.

The source is the canonical artifact. Do not edit generated files and expect edits to survive another build. No automatic deployment is configured.

## Content and licensing

The alpha section accurately states that a verified public download is not available yet. Replace it with the release download only after the signed, notarized artifact passes release checks; include the actual tested macOS and hardware coverage.

Product previews use the native app renderer and fixture data; native glass uses the opaque preview fallback. `COMPONENTS_LICENSE.txt` preserves the upstream notice for vendored shadcn components. The build collects dependency notices from packages included in browser chunks. The checked-in Vite RSC fallback notice comes from [Vite's upstream license](https://github.com/vitejs/vite-plugin-react/blob/main/LICENSE), because the installed package omits a license file.
