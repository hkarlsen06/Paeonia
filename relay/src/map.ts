/**
 * Map proxy. The Us tab's map loads its style, tiles, glyphs and sprites from
 * OpenFreeMap through this route, so OpenFreeMap gets requests from Cloudflare
 * and never from a phone. Cloudflare sets `CF-Connecting-IP` on a request from a
 * Worker to another Cloudflare zone to its own address, and this file builds
 * every upstream request from the path alone, so nothing of the phone's request
 * goes upstream.
 */
export const MAP_PREFIX = "/map";
const UPSTREAM = "https://tiles.openfreemap.org";

const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

type Json = Record<string, unknown>;
type ThroughProxy = (url: unknown) => string;

/** One kind of OpenFreeMap file the app loads. A path that matches none is refused. */
interface MapResource {
  /** Matches the whole decoded upstream path. */
  path: RegExp;
  /** How long the edge cache and the phone keep the file, in seconds. */
  maxAge: number;
  /** Points the URLs inside a JSON file back at the proxy. */
  rewrite?: (document: Json, throughProxy: ThroughProxy) => Json;
}

const RESOURCES: MapResource[] = [
  { path: /^\/styles\/dark$/, maxAge: HOUR, rewrite: rewriteStyle },
  // The tile list names the current planet build. It is short-lived so a new build
  // shows soon, and so the app's check of the map reaches OpenFreeMap during an outage.
  { path: /^\/planet$/, maxAge: 10 * MINUTE, rewrite: rewriteTiles },
  // A tile's path holds its planet build and a sprite's path holds a hash, so neither changes.
  { path: /^\/planet\/\w+\/\d{1,2}\/\d{1,8}\/\d{1,8}\.pbf$/, maxAge: 30 * DAY },
  { path: /^\/sprites\/[\w-]+\/[\w-]+(@2x)?\.(json|png)$/, maxAge: 30 * DAY },
  { path: /^\/fonts\/[\w ,-]+\/\d{1,5}-\d{1,5}\.pbf$/, maxAge: 7 * DAY },
];

const TILE_SOURCE_TYPES = new Set(["vector", "raster", "raster-dem"]);

export interface MapProxyRuntime {
  fetch(url: string, init: { redirect: "manual" }): Promise<Response>;
  cache: { match(request: Request): Promise<Response | undefined>; put(request: Request, response: Response): Promise<void> };
  waitUntil(promise: Promise<unknown>): void;
}

export async function proxyMap(request: Request, runtime: MapProxyRuntime): Promise<Response> {
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  const url = new URL(request.url);
  const target = upstreamTarget(url.pathname);
  if (!target) return new Response("Not found", { status: 404 });
  const { resource, path } = target;
  const proxy = url.origin + MAP_PREFIX;
  // The key has no query string and no headers, so a caller can't fill the cache with copies.
  const cacheKey = new Request(proxy + path);
  const cached = await runtime.cache.match(cacheKey);
  if (cached) return cached;

  let upstream: Response;
  try {
    upstream = await runtime.fetch(UPSTREAM + path, { redirect: "manual" });
  } catch {
    return unavailable("The map server could not be reached");
  }
  // A redirect would send the phone to its target directly.
  if (upstream.status >= 300 && upstream.status < 400) return unavailable("The map server answered with a redirect");
  const headers = new Headers({ "X-Content-Type-Options": "nosniff" });
  const contentType = upstream.headers.get("Content-Type");
  if (contentType) headers.set("Content-Type", contentType);
  if (!upstream.ok) {
    headers.set("Cache-Control", "no-store");
    return new Response(upstream.body, { status: upstream.status, headers });
  }

  let body: BodyInit | null = upstream.body;
  if (resource.rewrite) {
    try {
      body = JSON.stringify(resource.rewrite(await upstream.json(), (inner) => throughProxy(inner, proxy)));
    } catch {
      return unavailable("The map server sent a file the proxy does not understand");
    }
  }
  headers.set("Cache-Control", `public, max-age=${resource.maxAge}`);
  const response = new Response(body, { status: upstream.status, headers });
  runtime.waitUntil(runtime.cache.put(cacheKey, response.clone()));
  return response;
}

function upstreamTarget(pathname: string): { resource: MapResource; path: string } | null {
  if (!pathname.startsWith(`${MAP_PREFIX}/`)) return null;
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname.slice(MAP_PREFIX.length));
  } catch {
    return null;
  }
  const resource = RESOURCES.find((candidate) => candidate.path.test(decoded));
  return resource ? { resource, path: encodeURI(decoded) } : null;
}

function unavailable(message: string): Response {
  return new Response(message, { status: 502, headers: { "Cache-Control": "no-store" } });
}

/** Throws for a URL on any other host, so the phone is never handed one. */
function throughProxy(url: unknown, proxy: string): string {
  if (typeof url !== "string" || !url.startsWith(`${UPSTREAM}/`)) throw new Error("Not an OpenFreeMap URL");
  return proxy + url.slice(UPSTREAM.length);
}

function rewriteStyle(style: Json, throughProxy: ThroughProxy): Json {
  const sources = Object.entries(style.sources as Record<string, Json>).map(([name, source]) => {
    // Other kinds of source keep their URLs in fields this file does not rewrite.
    if (!TILE_SOURCE_TYPES.has(source.type as string)) throw new Error("Not a tile source");
    return [name, rewriteTiles(source, throughProxy)];
  });
  return {
    ...style,
    sources: Object.fromEntries(sources),
    sprite: throughProxy(style.sprite),
    glyphs: throughProxy(style.glyphs),
  };
}

/** A tile source in a style and a tile list have the same two URL fields. */
function rewriteTiles(source: Json, throughProxy: ThroughProxy): Json {
  return {
    ...source,
    ...("url" in source && { url: throughProxy(source.url) }),
    ...("tiles" in source && { tiles: (source.tiles as unknown[]).map(throughProxy) }),
  };
}
