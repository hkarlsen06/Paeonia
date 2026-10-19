/**
 * Tickets come from `widget:create_widget_live_ticket` and `games:create_game_live_ticket` in Convex:
 * `base64url(JSON {c: coupleId, u: userId, e: expiresAtMs, ch?: channel}).hex(hmacSha256(payload))`.
 * Convex already checked that the user may draw with this couple.
 * Without `ch` the socket joins the couple's widget canvas room. With `ch` it joins the
 * couple's room for that channel, so a game does not share the canvas room's socket cap.
 */
export type Ticket = { coupleId: string; userId: string; expiresAt: number; channel?: string };

/**
 * The channels a ticket may name. The channel is the game kind, and Convex issues tickets for every
 * kind in `GAME_KINDS` (backend/convex/lib/validators.ts). Keep the two lists the same.
 */
export const ALLOWED_CHANNELS: readonly string[] = [
  "draw_and_guess",
  "mind_meld",
  "exquisite_corpse",
  "story_chain",
  "connect_four",
  "dots_and_boxes",
  "ultimate_tic_tac_toe",
  "ludo",
  "consensio",
  "guess_my_spot",
];

/** The Durable Object name for a ticket's room. */
export function roomName(ticket: Ticket): string {
  return ticket.channel === undefined ? ticket.coupleId : `${ticket.coupleId}:${ticket.channel}`;
}

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
    if (claims.ch === undefined) return { coupleId: claims.c, userId: claims.u, expiresAt: claims.e };
    if (typeof claims.ch !== "string" || !ALLOWED_CHANNELS.includes(claims.ch)) return null;
    return { coupleId: claims.c, userId: claims.u, expiresAt: claims.e, channel: claims.ch };
  } catch {
    return null;
  }
}
