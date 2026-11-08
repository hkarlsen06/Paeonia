import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { assertEditable, pngDimensions, root, withAsc } from './lib/app-store-connect.mjs';
import { seedVersionMetadata } from '../ios/Scripts/appstore-metadata-files.mjs';

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMIUDAAAAFkAKGRCa6OAAAAAElFTkSuQmCC', 'base64');

test('the upload parser accepts finished artwork and rejects truncated files', () => {
  assert.deepEqual(pngDimensions(png, 'artwork'), [1, 1]);
  for (const length of [0, 20, 33, png.length - 1]) {
    assert.throws(() => pngDimensions(png.subarray(0, length), 'truncated'), /invalid|incomplete|truncated/);
  }
});

test('alpha channels and RGB transparency are rejected before uploading', () => {
  const alpha = Buffer.from(png);
  alpha[25] = 6;
  assert.throws(() => pngDimensions(alpha, 'alpha'), /opaque RGB/);
  const transparent = Buffer.alloc(18);
  transparent.writeUInt32BE(6);
  transparent.write('tRNS', 4, 'ascii');
  assert.throws(() => pngDimensions(Buffer.concat([png.subarray(0, 33), transparent, png.subarray(33)]), 'transparent'), /transparency/);
});

test('applying changes rejects released or reviewing versions', () => {
  for (const state of ['READY_FOR_DISTRIBUTION', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE', undefined]) {
    assert.throws(() => assertEditable({ attributes: { versionString: '1.0.0', appVersionState: state } }), /editable version/);
  }
  assert.throws(() => assertEditable({ attributes: { versionString: '1.0.0', appStoreState: 'READY_FOR_SALE' } }), /editable version/);
  assert.doesNotThrow(() => assertEditable({ attributes: { versionString: '1.0.1', appVersionState: 'PREPARE_FOR_SUBMISSION' } }));
});

test('credentials get a private temporary copy and read-only calls keep their write barrier after failure', async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'paeonia-asc-test-'));
  const file = path.join(temporary, 'test-key.p8');
  await writeFile(file, 'test key', { mode: 0o644 });
  const before = process.env.ASC_PRIVATE_KEY_PATH;
  process.env.ASC_PRIVATE_KEY_PATH = file;
  let copy;
  try {
    await assert.rejects(withAsc(async (_asc, env) => {
      copy = env.ASC_PRIVATE_KEY_PATH;
      assert.notEqual(copy, file);
      assert.equal((await stat(copy)).mode & 0o777, 0o600);
      assert.equal(await readFile(copy, 'utf8'), 'test key');
      assert.equal(env.ASC_READ_ONLY, '1');
      throw new Error('interrupted');
    }), /interrupted/);
    await assert.rejects(stat(copy), { code: 'ENOENT' });
    assert.equal(await readFile(file, 'utf8'), 'test key');
  } finally {
    if (before === undefined) delete process.env.ASC_PRIVATE_KEY_PATH;
    else process.env.ASC_PRIVATE_KEY_PATH = before;
    await rm(temporary, { recursive: true, force: true });
  }
});

test('a new release preserves reviewed translations and URLs without taking a future version or overwriting edits', async () => {
  const metadata = await mkdtemp(path.join(os.tmpdir(), 'paeonia-metadata-test-'));
  const previous = { description: 'Reviewed Norwegian description', promotionalText: 'Reviewed promotion',
    supportUrl: 'https://paeonia.no/help', marketingUrl: 'https://paeonia.no', whatsNew: 'Reviewed notes' };
  try {
    for (const version of ['3.1.9', '3.1.10', '4.0.0']) {
      await mkdir(path.join(metadata, 'version', version), { recursive: true });
      await writeFile(path.join(metadata, 'version', version, 'no.json'), JSON.stringify(version === '3.1.10' ? previous : { description: version }));
    }
    assert.equal(await seedVersionMetadata(metadata, '3.1.11'), '3.1.10');
    const generated = path.join(metadata, 'version/3.1.11/no.json');
    assert.deepEqual(JSON.parse(await readFile(generated, 'utf8')), previous);
    await writeFile(generated, JSON.stringify({ ...previous, whatsNew: 'New approved notes' }));
    assert.equal(await seedVersionMetadata(metadata, '3.1.11'), null);
    assert.equal(JSON.parse(await readFile(generated, 'utf8')).whatsNew, 'New approved notes');
  } finally {
    await rm(metadata, { recursive: true, force: true });
  }
});

test('a review upload rejects unresolved reviewer codes before invoking ASC', async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'paeonia-review-test-'));
  try {
    for (const file of ['scripts/app-store.mjs', 'scripts/lib/app-store-connect.mjs', 'ios/Version.xcconfig', 'ios/app-store/config.json']) {
      await mkdir(path.dirname(path.join(temporary, file)), { recursive: true });
      await cp(path.join(root, file), path.join(temporary, file));
    }
    const metadata = path.join(temporary, 'ios/app-store/metadata');
    await mkdir(path.join(metadata, 'version/1.0.0'), { recursive: true });
    await writeFile(path.join(metadata, 'version/1.0.0/en-US.json'), JSON.stringify({ promotionalText: 'Test promotion' }));
    await writeFile(path.join(metadata, 'review-information.json'), JSON.stringify({ notes: 'Use {{REVIEW_CODES}} to join.' }));
    await assert.rejects(promisify(execFile)(process.execPath, [path.join(temporary, 'scripts/app-store.mjs'), 'review-metadata', '--apply', '--version', '1.0.0'], {
      env: { ...process.env, ASC_BIN: path.join(temporary, 'must-not-be-invoked') },
    }), error => {
      assert.match(error.stderr, /Review notes still contain \{\{REVIEW_CODES\}\}/);
      return true;
    });
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});
