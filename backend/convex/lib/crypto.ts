import { stableStringify } from "./json";

const encoder = new TextEncoder();

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(input: string | Uint8Array): Promise<string> {
  const data = typeof input === "string" ? encoder.encode(input) : input;
  return toHex(await crypto.subtle.digest("SHA-256", data as BufferSource));
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}

/** Random lowercase hex string of `bytes` random bytes. */
export function randomHex(bytes = 32): string {
  return toHex(crypto.getRandomValues(new Uint8Array(bytes)).buffer as ArrayBuffer);
}

/** Random URL-safe token (base64url without padding) of `bytes` random bytes. */
export function randomToken(bytes = 32): string {
  const raw = crypto.getRandomValues(new Uint8Array(bytes));
  let binary = "";
  for (const byte of raw) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Compares two strings without returning early on the first difference. */
export function timingSafeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}

/** Request hash for client operations: sha256 of the stable JSON encoding of the fields. */
export function requestHash(fields: unknown): Promise<string> {
  return sha256Hex(stableStringify(fields));
}
