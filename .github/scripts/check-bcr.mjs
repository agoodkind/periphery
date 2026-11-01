import { appendFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export async function checkPublication(version, registryURL) {
  if (!/^\d+\.\d+\.\d+-agoodkind\.\d+$/.test(version)) {
    throw new Error('Set VERSION to an agoodkind/periphery release version');
  }
  const url = new URL(`modules/agoodkind-periphery/${version}/source.json`, registryURL);
  const response = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(30000) });
  if (response.status !== 200 && response.status !== 404) {
    throw new Error(`Bazel registry publication check failed with HTTP ${response.status}`);
  }
  return response.status === 200;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) {
    throw new Error('Set GITHUB_OUTPUT before checking registry publication');
  }
  const published = await checkPublication(process.env.VERSION, new URL('https://bcr.bazel.build/'));
  await appendFile(outputPath, `published=${published}\n`);
}
