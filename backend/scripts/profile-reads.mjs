// Compare two isolated backends loaded from the same snapshot. Never writes app data.
// BEFORE_ADMIN_KEY=... AFTER_ADMIN_KEY=... node scripts/profile-reads.mjs \
//   <before-url> <after-url> <clerk-subject> <output.json>
// Run from backend/. PROFILE_ARTIFACT_MANIFEST names optional revision/fixture hash metadata.
// PROFILE_HEAD_ONLY_PATHS is a comma-separated list of paths that only the after side has. They are
// measured on the after side only and reported without a comparison.
// The report stays incomplete if any request or comparison fails.
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { ConvexClient, ConvexHttpClient } from 'convex/browser';

const [beforeURL, afterURL, subject, output] = process.argv.slice(2);
if (!beforeURL || !afterURL || !subject || !output) {
  throw new Error('Expected before URL, after URL, Clerk subject, and output JSON path');
}
const sides = [
  { name: 'before', url: beforeURL, key: process.env.BEFORE_ADMIN_KEY },
  { name: 'after', url: afterURL, key: process.env.AFTER_ADMIN_KEY },
];
for (const side of sides) {
  if (!side.key) throw new Error(`Missing ${side.name} admin key`);
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(new URL(side.url).hostname)) {
    throw new Error('Use isolated local backends for this comparison');
  }
}
const paths = [
  'access:get_access_snapshot', 'widget:get_widget_canvas',
  'daily:get_today_daily_challenge_snapshot', 'threads:get_conversation_threads',
  'games:get_games_overview', 'memories:get_memories',
  'stories:get_stories', 'topics:get_topics_overview',
];
const headOnlyPaths = (process.env.PROFILE_HEAD_ONLY_PATHS ?? '').split(',').map(path => path.trim()).filter(Boolean);
const pathsOf = side => side.name === 'after' ? [...paths, ...headOnlyPaths] : paths;
const report = { status: 'incomplete', startedAt: new Date().toISOString(),
  artifacts: null,
  headOnlyPaths, trials: [], telemetry: [] };
const save = () => writeFileSync(output, JSON.stringify(report, null, 2));
save();
const identity = (tokenIdentifier) => ({ subject, issuer: 'https://clerk.paeonia.no', tokenIdentifier });
const argsFor = (path, trial) => path.startsWith('daily:') ? { p_day_key: `profile-${trial}` } : {};
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}
function comparable(path, value) {
  // Discovery's generated_at is the server clock at execution, not relationship content.
  const normalized = path.startsWith('daily:') ? value.map(({ generated_at, ...row }) => row) : value;
  return JSON.stringify(canonical(normalized));
}
const hash = value => createHash('sha256').update(value).digest('hex');
async function telemetry(side, cursor = 0) {
  const response = await fetch(`${side.url}/api/stream_function_logs?cursor=${cursor}`, {
    headers: { Authorization: `Convex ${side.key}` }, signal: AbortSignal.timeout(30000),
  });
  assert.equal(response.status, 200);
  return response.json();
}
async function httpBundle(side, trial, condition) {
  const client = new ConvexHttpClient(side.url, { logger: false });
  client.setAdminAuth(side.key, identity(trial));
  const results = [];
  for (const path of pathsOf(side)) {
    const start = performance.now();
    const value = await client.query(path, argsFor(path, trial));
    results.push({ path, ms: performance.now() - start, hash: hash(comparable(path, value)),
      bytes: Buffer.byteLength(JSON.stringify(value)) });
  }
  return { side: side.name, transport: 'http', condition, results };
}
async function liveBundle(side, trial) {
  const client = new ConvexClient(side.url, { logger: false, unsavedChangesWarning: false });
  client.setAdminAuth(side.key, identity(trial));
  const start = performance.now();
  const unsubscribes = [];
  try {
    const results = await Promise.all(pathsOf(side).map(path => new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`${path} first-value timeout`)), 30000);
      unsubscribes.push(client.onUpdate(path, argsFor(path, trial), value => {
        clearTimeout(timer);
        resolve({ path, ms: performance.now() - start, hash: hash(comparable(path, value)),
          bytes: Buffer.byteLength(JSON.stringify(value)) });
      }, error => { clearTimeout(timer); reject(error); }));
    })));
    return { side: side.name, transport: 'websocket', condition: 'warm-reconnect',
      allReadyMs: Math.max(...results.map(row => row.ms)), results };
  } finally {
    unsubscribes.forEach(unsubscribe => unsubscribe());
    await client.close();
  }
}
function compare(pair) {
  const shared = row => row.results.filter(({ path }) => paths.includes(path)).map(({ path, hash }) => ({ path, hash }));
  assert.deepEqual(shared(pair[0]), shared(pair[1]), 'Response mismatch between revisions');
}
try {
  if (process.env.PROFILE_ARTIFACT_MANIFEST) {
    report.artifacts = JSON.parse(readFileSync(process.env.PROFILE_ARTIFACT_MANIFEST, 'utf8'));
  }
  const cursors = new Map();
  for (const side of sides) cursors.set(side.name, (await telemetry(side)).newCursor);
  report.startCursors = Object.fromEntries(cursors);
  save();
  for (let trial = 0; trial < 5; trial++) {
    const id = randomUUID();
    for (const condition of ['fresh-execution', 'warm']) {
      const pair = [];
      for (const side of sides) {
        const row = await httpBundle(side, id, condition);
        pair.push(row); report.trials.push({ trial, ...row }); save();
      }
      compare(pair);
    }
    const pair = [];
    for (const side of sides) {
      const row = await liveBundle(side, id);
      pair.push(row); report.trials.push({ trial, ...row }); save();
    }
    compare(pair);
  }
  // Existing server telemetry is collected after timing, without enabling a profiler.
  for (const side of sides) {
    const cursor = cursors.get(side.name);
    const { entries, newCursor } = await telemetry(side, cursor);
    report.telemetry.push({ side: side.name, startCursor: cursor, endCursor: newCursor,
      entries: entries.filter(row => row.timestamp * 1000 > cursor && pathsOf(side).includes(row.identifier)).map(row => ({
      timestamp: row.timestamp, requestId: row.requestId, executionId: row.executionId,
      path: row.identifier, cached: row.cachedResult, ms: row.executionTime * 1000,
      reads: row.usageStats.databaseReadDocuments, readBytes: row.usageStats.databaseReadBytes,
      memoryMb: row.usageStats.memoryUsedMb, caller: row.caller, error: row.error,
    })) });
  }
  report.status = 'complete'; report.completedAt = new Date().toISOString(); save();
  console.log(JSON.stringify({ status: report.status,
    requestsAndFirstValues: report.trials.reduce((sum, trial) => sum + trial.results.length, 0),
    comparedPairs: report.trials.length / 2, output }));
} catch (error) {
  report.error = String(error); save(); throw error;
}
