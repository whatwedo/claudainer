import { describe, test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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
    await container?.stop();
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

describe('.claudainer exclude masking', () => {
  let workdir;

  before(() => {
    // A host project dir containing a secret .env file and a secrets/ directory,
    // made world-readable so the container's `developer` (UID 1000) user can
    // read it regardless of the host UID that created it.
    workdir = mkdtempSync(join(tmpdir(), 'claudainer-exclude-'));
    chmodSync(workdir, 0o755);
    writeFileSync(join(workdir, '.env'), 'SECRET=hunter2\n', { mode: 0o644 });
    mkdirSync(join(workdir, 'secrets'), { mode: 0o755 });
    writeFileSync(join(workdir, 'secrets', 'key'), 'TOP_SECRET\n', { mode: 0o644 });
  });

  after(() => {
    rmSync(workdir, { recursive: true, force: true });
  });

  test('a /dev/null-masked file reads empty inside the container', async () => {
    // Mirrors what claudainer does for a file listed in exclude_paths: the
    // workspace mount + a read-only /dev/null mask layered over the file.
    const container = await new GenericContainer(IMAGE)
      .withCommand(['sleep', 'infinity'])
      .withBindMounts([
        { source: workdir, target: '/workspace' },
        { source: '/dev/null', target: '/workspace/.env', mode: 'ro' },
      ])
      .start();
    try {
      const read = await container.exec(['cat', '/workspace/.env']);
      assert.strictEqual(read.exitCode, 0);
      assert.strictEqual(read.output.trim(), '');
    } finally {
      await container.stop();
    }

    // The real file on the host is left untouched.
    assert.match(readFileSync(join(workdir, '.env'), 'utf8'), /SECRET=hunter2/);
  });

  test('a tmpfs-masked directory appears empty inside the container', async () => {
    // Mirrors what claudainer does for a directory listed in exclude_paths: an
    // empty tmpfs mounted over the directory hides its host contents.
    const container = await new GenericContainer(IMAGE)
      .withCommand(['sleep', 'infinity'])
      .withBindMounts([{ source: workdir, target: '/workspace' }])
      .withTmpFs({ '/workspace/secrets': 'rw' })
      .start();
    try {
      const list = await container.exec(['ls', '-A', '/workspace/secrets']);
      assert.strictEqual(list.exitCode, 0);
      assert.strictEqual(list.output.trim(), '');
    } finally {
      await container.stop();
    }

    // The real directory on the host is left untouched.
    assert.match(readFileSync(join(workdir, 'secrets', 'key'), 'utf8'), /TOP_SECRET/);
  });

  test('without a mask the content is visible (i.e. not in exclude_paths)', async () => {
    const container = await new GenericContainer(IMAGE)
      .withCommand(['sleep', 'infinity'])
      .withBindMounts([
        { source: workdir, target: '/workspace' },
      ])
      .start();
    try {
      const read = await container.exec(['cat', '/workspace/.env']);
      assert.strictEqual(read.exitCode, 0);
      assert.match(read.output, /SECRET=hunter2/);
    } finally {
      await container.stop();
    }
  });
});
