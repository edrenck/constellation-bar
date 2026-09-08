import { readFile, readdir, access } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import type { Plugin } from 'vite';

// Include the original notices for packages actually present in client chunks.
export function thirdPartyNotices(): Plugin {
  return {
    name: 'constellation-third-party-notices',
    apply: 'build',
    async generateBundle(_options, bundle) {
      if (this.environment.name !== 'client') return;
      const packages = new Set<string>();
      for (const chunk of Object.values(bundle)) {
        if (chunk.type !== 'chunk') continue;
        for (const id of Object.keys(chunk.modules)) {
          if (!id.includes('/node_modules/') || id.startsWith('\0')) continue;
          let directory = dirname(id.split('?')[0]);
          while (directory.includes('/node_modules/')) {
            try { await access(join(directory, 'package.json')); packages.add(directory); break; }
            catch { directory = dirname(directory); }
          }
        }
      }
      const notices = ['ConstellationBar website — third-party notices',
        'This file contains license notices for packages included in the browser bundle and the vendored component source.',
        await readFile(resolve('..', 'LICENSE'), 'utf8'),
        await readFile(resolve('COMPONENTS_LICENSE.txt'), 'utf8')];
      for (const directory of [...packages].sort()) {
        const manifest = JSON.parse(await readFile(join(directory, 'package.json'), 'utf8'));
        const files = (await readdir(directory)).filter(name => /^(licen[cs]e|copying|notice)(\.|-|$)/i.test(name));
        notices.push(`\n${'='.repeat(72)}\n${manifest.name} ${manifest.version}\n`);
        if (!files.length) {
          const fallback = resolve('licenses', `${manifest.name.replaceAll('/', '__')}.txt`);
          try { notices.push(await readFile(fallback, 'utf8')); }
          catch { throw new Error(`Missing upstream license notice for bundled package ${manifest.name}`); }
        }
        for (const file of files) {
          try { notices.push(await readFile(join(directory, file), 'utf8')); }
          catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EISDIR') throw error; }
        }
      }
      this.emitFile({type: 'asset', fileName: 'THIRD_PARTY_NOTICES.txt', source: notices.join('\n\n')});
    },
  };
}
