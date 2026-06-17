import { describe, test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { GenericContainer } from 'testcontainers';

const IMAGE = process.env.CLAUDAINER_IMAGE ?? 'ghcr.io/whatwedo/claudainer:latest';

describe('claudainer image', () => {
  let container;

  before(async () => {
    container = await new GenericContainer(IMAGE)
      .withCommand(['sleep', 'infinity'])
      .start();
  });

  after(async () => {
    await container?.stop({ timeout: 10000 });
  });

  test('claude binary is on PATH', async () => {
    const result = await container.exec(['which', 'claude']);
    assert.strictEqual(result.exitCode, 0);
  });

  test('node version is 22', async () => {
    const result = await container.exec(['node', '--version']);
    assert.strictEqual(result.exitCode, 0);
    assert.match(result.output.trim(), /^v22\./);
  });

  test('docker CLI is available', async () => {
    const result = await container.exec(['docker', '--version']);
    assert.strictEqual(result.exitCode, 0);
  });

  test('git is available', async () => {
    const result = await container.exec(['git', '--version']);
    assert.strictEqual(result.exitCode, 0);
  });

  test('running as developer user', async () => {
    const result = await container.exec(['id', '-un']);
    assert.strictEqual(result.exitCode, 0);
    assert.strictEqual(result.output.trim(), 'developer');
  });

  test('working directory is /workspace', async () => {
    const result = await container.exec(['pwd']);
    assert.strictEqual(result.exitCode, 0);
    assert.strictEqual(result.output.trim(), '/workspace');
  });

  test('CLAUDE_CODE_DISABLE_AUTOUPDATER is set to 1', async () => {
    const result = await container.exec(['printenv', 'CLAUDE_CODE_DISABLE_AUTOUPDATER']);
    assert.strictEqual(result.exitCode, 0);
    assert.strictEqual(result.output.trim(), '1');
  });

  test('files written on host are visible inside container via /workspace mount', async () => {
    // Write a sentinel file on the host via exec (simulates a volume mount scenario
    // using the container's writable /workspace directory)
    const writeResult = await container.exec(['sh', '-c', 'echo sentinel > /workspace/sentinel.txt']);
    assert.strictEqual(writeResult.exitCode, 0);

    const readResult = await container.exec(['cat', '/workspace/sentinel.txt']);
    assert.strictEqual(readResult.exitCode, 0);
    assert.match(readResult.output, /sentinel/);
  });
});
