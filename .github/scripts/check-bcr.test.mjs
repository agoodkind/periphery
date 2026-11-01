import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';

import { checkPublication } from './check-bcr.mjs';

test('Reject a release version without the agoodkind suffix', async () => {
  await assert.rejects(checkPublication('3.9.12', new URL('https://bcr.bazel.build/')), {
    message: 'Set VERSION to an agoodkind/periphery release version',
  });
});

for (const status of [200, 404, 503]) {
  test(`Check registry publication with HTTP ${status}`, async (context) => {
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
      await assert.rejects(checkPublication('3.9.12-agoodkind.1', registryURL), /HTTP 503/);
    } else {
      const published = await checkPublication('3.9.12-agoodkind.1', registryURL);
      assert.equal(published, status === 200);
    }
  });
}
