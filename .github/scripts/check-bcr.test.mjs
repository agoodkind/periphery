import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { checkPublication } from './check-bcr.mjs';

for (const status of [200, 404, 503]) {
  test(`Check registry publication with HTTP ${status}`, async (context) => {
    const directory = await mkdtemp(join(tmpdir(), 'periphery-bcr-'));
    context.after(() => rm(directory, { recursive: true }));
    const outputPath = join(directory, 'output');
    const server = createServer((request, response) => {
      if (request.url === '/modules/agoodkind-periphery/3.9.12-agoodkind.1/source.json') {
        response.writeHead(status);
      } else {
        response.writeHead(404);
      }
      response.end();
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    context.after(() => new Promise((resolve) => server.close(resolve)));
    const registryURL = new URL(`http://127.0.0.1:${server.address().port}/`);
    if (status === 503) {
      await assert.rejects(checkPublication('3.9.12-agoodkind.1', registryURL, outputPath), /HTTP 503/);
      await assert.rejects(readFile(outputPath), { code: 'ENOENT' });
    } else {
      await checkPublication('3.9.12-agoodkind.1', registryURL, outputPath);
      assert.equal(await readFile(outputPath, 'utf8'), `published=${status === 200}\n`);
    }
  });
}
