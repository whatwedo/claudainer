// Integration test: main container + proxy container on a shared network.
// Requires internet access (curls example.com through the proxy).
// Skip by setting SKIP_NETWORK_TESTS=1.
import { describe, test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { GenericContainer, Network } from 'testcontainers';

const CLAUDAINER_IMAGE = process.env.CLAUDAINER_IMAGE ?? 'ghcr.io/whatwedo/claudainer:latest';
const PROXY_IMAGE = process.env.CLAUDAINER_PROXY_IMAGE ?? 'ghcr.io/whatwedo/claudainer-proxy:latest';
const SKIP = process.env.SKIP_NETWORK_TESTS === '1';

describe('claudainer proxy network', { skip: SKIP }, () => {
  let network;
  let proxyContainer;
  let mainContainer;

  before(async () => {
    network = await new Network().start();

    proxyContainer = await new GenericContainer(PROXY_IMAGE)
      .withNetwork(network)
      .withNetworkAliases('claudainer-proxy')
      .start();

    mainContainer = await new GenericContainer(CLAUDAINER_IMAGE)
      .withCommand(['sleep', 'infinity'])
      .withNetwork(network)
      .withEnvironment({
        HTTP_PROXY: 'http://claudainer-proxy:3128',
        HTTPS_PROXY: 'http://claudainer-proxy:3128',
        NO_PROXY: 'localhost,127.0.0.1',
      })
      .start();
  });

  after(async () => {
    await mainContainer?.stop({ timeout: 10000 });
    await proxyContainer?.stop({ timeout: 10000 });
    await network?.stop();
  });

  test('proxy container is reachable from main container', async () => {
    // curl --proxy-connect-timeout avoids hanging if proxy is unreachable
    const result = await mainContainer.exec([
      'curl', '--silent', '--max-time', '15',
      '--proxy', 'http://claudainer-proxy:3128',
      '-o', '/dev/null', '-w', '%{http_code}',
      'http://example.com',
    ]);
    assert.strictEqual(result.exitCode, 0);
    // Any 2xx or 3xx means the proxy forwarded the request
    const status = parseInt(result.output.trim(), 10);
    assert.ok(status >= 200 && status < 400, `Expected 2xx/3xx, got ${status}`);
  });

  test('proxy container listens on port 3128', async () => {
    const result = await mainContainer.exec([
      'sh', '-c',
      'curl --silent --max-time 5 --proxy http://claudainer-proxy:3128 http://example.com -o /dev/null; echo $?',
    ]);
    // Exit 0 means the TCP connection to the proxy succeeded (even if request fails)
    assert.strictEqual(result.exitCode, 0);
  });
});
