/**
 * Tickets come from `widget:create_widget_live_ticket` in Convex:
 * `base64url(JSON {c: coupleId, u: userId, e: expiresAtMs}).hex(hmacSha256(payload))`.
 * Convex already checked that the user may draw with this couple.
 */
export type Ticket = { coupleId: string; userId: string; expiresAt: number };

const encoder = new TextEncoder();

export async function verifyTicket(raw: string, secret: string, now: number): Promise<Ticket | null> {
  const [payload, signature, extra] = raw.split(".");
  if (!payload || !signature || extra !== undefined || !/^[0-9a-f]{64}$/.test(signature)) return null;
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const signatureBytes = new Uint8Array(signature.match(/../g)!.map((byte) => parseInt(byte, 16)));
  // `verify` compares in constant time.
  if (!(await crypto.subtle.verify("HMAC", key, signatureBytes, encoder.encode(payload)))) return null;
  try {
    const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    if (typeof claims.c !== "string" || typeof claims.u !== "string" || typeof claims.e !== "number") return null;
    if (claims.e <= now) return null;
    return { coupleId: claims.c, userId: claims.u, expiresAt: claims.e };
  } catch {
    return null;
  }
}
