import assert from "node:assert/strict";
import { test } from "node:test";
import { proxyMap } from "./map.ts";

const proxy = "https://relay.paeonia.no/map";
const upstream = "https://tiles.openfreemap.org";

const style = {
  version: 8,
  sources: {
    ne2_shaded: { type: "raster", maxzoom: 6, tiles: [`${upstream}/natural_earth/ne2sr/{z}/{x}/{y}.png`] },
    openmaptiles: { type: "vector", url: `${upstream}/planet` },
  },
  sprite: `${upstream}/sprites/ofm_f384/ofm`,
  glyphs: `${upstream}/fonts/{fontstack}/{range}.pbf`,
  layers: [{ id: "water", type: "fill", source: "openmaptiles" }],
};

const tileList = {
  tilejson: "3.0.0",
  tiles: [`${upstream}/planet/20261115_080022_pt/{z}/{x}/{y}.pbf`],
  attribution: '<a href="https://openfreemap.org">OpenFreeMap</a>',
};

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json", "Set-Cookie": "id=1" } });
}

/** A proxy in front of a fake OpenFreeMap that answers every path with `answer`. */
function setUp(answer: (url: string) => Response | Promise<Response>, allowed = true) {
  const upstreamRequests: Request[] = [];
  const cached = new Map<string, Response>();
  const pending: Promise<unknown>[] = [];
  const runtime = {
    fetch: async (url: string, init: RequestInit) => {
      upstreamRequests.push(new Request(url, init));
      return answer(url);
    },
    cache: {
      match: async (request: Request) => cached.get(request.url)?.clone(),
      put: async (request: Request, response: Response) => void cached.set(request.url, response),
    },
    waitUntil: (promise: Promise<unknown>) => void pending.push(promise),
    allow: async () => allowed,
  };
  return {
    upstreamRequests,
    cached,
    async get(path: string, init?: RequestInit): Promise<Response> {
      const response = await proxyMap(new Request(proxy + path, init), runtime);
      await Promise.all(pending);
      return response;
    },
  };
}

test("the style's URLs all point back at the proxy", async () => {
  const map = setUp(() => json(style));
  const response = await map.get("/styles/dark");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ...style,
    sources: {
      ne2_shaded: { type: "raster", maxzoom: 6, tiles: [`${proxy}/natural_earth/ne2sr/{z}/{x}/{y}.png`] },
      openmaptiles: { type: "vector", url: `${proxy}/planet` },
    },
    sprite: `${proxy}/sprites/ofm_f384/ofm`,
    glyphs: `${proxy}/fonts/{fontstack}/{range}.pbf`,
  });
  assert.equal(map.upstreamRequests[0].url, `${upstream}/styles/dark`);
});

test("the tile list's tile URLs point back at the proxy", async () => {
  const map = setUp(() => json(tileList));
  const response = await map.get("/planet");
  assert.deepEqual(await response.json(), { ...tileList, tiles: [`${proxy}/planet/20261115_080022_pt/{z}/{x}/{y}.pbf`] });
});

test("a rewritten style follows the origin the phone asked", async () => {
  const local = await proxyMap(new Request("http://localhost:8787/map/styles/dark"), {
    fetch: async () => json(style),
    cache: { match: async () => undefined, put: async () => {} },
    waitUntil: () => {},
    allow: async () => true,
  });
  assert.equal((await local.json()).glyphs, "http://localhost:8787/map/fonts/{fontstack}/{range}.pbf");
});

test("tiles, glyphs and sprites come back as OpenFreeMap sent them", async () => {
  const bytes = new Uint8Array([0x1f, 0x8b, 0, 255, 7]);
  const paths: Record<string, string> = {
    "/planet/20261115_080022_pt/14/8712/4747.pbf": `${upstream}/planet/20261115_080022_pt/14/8712/4747.pbf`,
    "/fonts/Noto%20Sans%20Regular/0-255.pbf": `${upstream}/fonts/Noto%20Sans%20Regular/0-255.pbf`,
    "/fonts/Noto%20Sans%20Regular,Noto%20Sans%20Bold/65280-65535.pbf": `${upstream}/fonts/Noto%20Sans%20Regular,Noto%20Sans%20Bold/65280-65535.pbf`,
    "/sprites/ofm_f384/ofm.json": `${upstream}/sprites/ofm_f384/ofm.json`,
    "/sprites/ofm_f384/ofm@2x.png": `${upstream}/sprites/ofm_f384/ofm@2x.png`,
  };
  for (const [path, upstreamURL] of Object.entries(paths)) {
    const map = setUp(() => new Response(bytes, { headers: { "Content-Type": "application/x-protobuf" } }));
    const response = await map.get(path);
    assert.equal(response.status, 200, path);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes, path);
    assert.equal(response.headers.get("Content-Type"), "application/x-protobuf", path);
    assert.equal(map.upstreamRequests[0].url, upstreamURL, path);
  }
});

test("nothing from the phone's request goes upstream", async () => {
  const map = setUp(() => json(style));
  await map.get("/styles/dark?user=42", {
    headers: {
      Cookie: "session=abc",
      Authorization: "Bearer ticket",
      "User-Agent": "Paeonia/1.0 iPhone",
      "X-Forwarded-For": "203.0.113.7",
      "CF-Connecting-IP": "203.0.113.7",
      "X-Real-IP": "203.0.113.7",
      "Accept-Language": "nb-NO",
      Referer: "https://paeonia.no/",
    },
  });
  const [sent] = map.upstreamRequests;
  assert.equal(sent.url, `${upstream}/styles/dark`);
  assert.deepEqual([...sent.headers], []);
  assert.equal(sent.method, "GET");
  assert.equal(sent.body, null);
});

test("OpenFreeMap's own headers stay behind", async () => {
  const map = setUp(() => json(style));
  const response = await map.get("/styles/dark");
  assert.deepEqual(
    [...response.headers.keys()].sort(),
    ["cache-control", "content-type", "x-content-type-options"],
  );
});

test("an answer is cached for as long as its kind allows", async () => {
  const lifetimes: Record<string, [Response, string]> = {
    "/styles/dark": [json(style), "public, max-age=3600"],
    "/planet": [json(tileList), "public, max-age=600"],
    "/planet/20261115_080022_pt/0/0/0.pbf": [new Response("tile"), "public, max-age=2592000"],
    "/sprites/ofm_f384/ofm.png": [new Response("sprite"), "public, max-age=2592000"],
    "/fonts/Noto%20Sans%20Regular/0-255.pbf": [new Response("glyphs"), "public, max-age=604800"],
  };
  for (const [path, [answer, cacheControl]] of Object.entries(lifetimes)) {
    const map = setUp(() => answer.clone());
    const first = await map.get(path);
    assert.equal(first.headers.get("Cache-Control"), cacheControl, path);
    const second = await map.get(`${path}?cache-buster=1`);
    assert.equal(map.upstreamRequests.length, 1, path);
    assert.equal(await second.text(), await first.text(), path);
  }
});

test("refuses every path that is not on the allowlist, without asking OpenFreeMap", async () => {
  const map = setUp(() => json(style));
  const refused = [
    "",
    "/",
    "/styles/liberty",
    "/styles/dark/",
    "/styles/dark/extra",
    "/natural_earth/ne2sr/0/0/0.png",
    "/planet/20261115_080022_pt/0/0/0.png",
    "/planet/20261115_080022_pt/0/0.pbf",
    "/planet/../styles/secret/0/0/0.pbf",
    "/planet/v%2F..%2F..%2Fother/0/0/0.pbf",
    "/fonts/a%2F..%2Fb/0-255.pbf",
    "/fonts/Noto%20Sans%20Regular/0-255.pbf%3Fx",
    "/fonts/%E0%A4%A/0-255.pbf",
    "/sprites/ofm_f384/ofm.js",
    "/sprites/ofm_f384/ofm@3x.png",
    "/https://example.com/styles/dark",
    "//example.com/styles/dark",
    "/%2F%2Fexample.com/styles/dark",
    "/styles/dark%00",
    "/b2/files",
  ];
  for (const path of refused) {
    assert.equal((await map.get(path)).status, 404, path);
  }
  assert.deepEqual(map.upstreamRequests, []);
  assert.equal(map.cached.size, 0);
});

test("a caller over the rate limit gets 429, without asking OpenFreeMap", async () => {
  const map = setUp(() => json(style), false);
  const response = await map.get("/styles/dark");
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.deepEqual(map.upstreamRequests, []);
  assert.equal(map.cached.size, 0);
});

test("refuses every method but GET", async () => {
  const map = setUp(() => json(style));
  for (const method of ["POST", "PUT", "DELETE", "HEAD", "OPTIONS"]) {
    assert.equal((await map.get("/styles/dark", { method })).status, 405, method);
  }
  assert.deepEqual(map.upstreamRequests, []);
});

test("an OpenFreeMap error comes back as it is and is not cached", async () => {
  for (const status of [403, 404, 429, 500, 503]) {
    const map = setUp(() => new Response(`upstream said ${status}`, { status, headers: { "Content-Type": "text/html" } }));
    const response = await map.get("/planet/20261115_080022_pt/0/0/0.pbf");
    assert.equal(response.status, status);
    assert.equal(await response.text(), `upstream said ${status}`);
    assert.equal(response.headers.get("Content-Type"), "text/html");
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.equal(map.cached.size, 0);
    await map.get("/planet/20261115_080022_pt/0/0/0.pbf");
    assert.equal(map.upstreamRequests.length, 2);
  }
});

test("answers 502, uncached, when OpenFreeMap can't be reached or redirects", async () => {
  const unreachable = setUp(() => {
    throw new TypeError("fetch failed");
  });
  assert.equal((await unreachable.get("/styles/dark")).status, 502);
  assert.equal(unreachable.cached.size, 0);

  const redirecting = setUp(() => new Response(null, { status: 302, headers: { Location: "https://example.com/styles/dark" } }));
  const response = await redirecting.get("/styles/dark");
  assert.equal(response.status, 502);
  assert.equal(response.headers.get("Location"), null);
  assert.equal(redirecting.cached.size, 0);
});

test("answers 502, uncached, for a style that would send the phone anywhere else", async () => {
  const elsewhere = [
    { ...style, glyphs: "https://fonts.example.com/{fontstack}/{range}.pbf" },
    { ...style, sprite: "https://tiles.openfreemap.org.example.com/sprites/ofm" },
    { ...style, sprite: [{ id: "default", url: `${upstream}/sprites/ofm_f384/ofm` }] },
    { ...style, sources: { ...style.sources, openmaptiles: { type: "vector", url: "https://example.com/planet" } } },
    { ...style, sources: { ...style.sources, places: { type: "geojson", data: "https://example.com/places.json" } } },
    { ...style, sources: undefined },
    "not a style",
  ];
  for (const answer of elsewhere) {
    const map = setUp(() => json(answer));
    assert.equal((await map.get("/styles/dark")).status, 502, JSON.stringify(answer));
    assert.equal(map.cached.size, 0);
  }
  const notJSON = setUp(() => new Response("<html>", { headers: { "Content-Type": "text/html" } }));
  assert.equal((await notJSON.get("/styles/dark")).status, 502);
});
