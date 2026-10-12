import { hmacSha256Hex } from "./crypto";

const LIVE_TICKET_TTL_MS = 60_000;

/**
 * Signs a short ticket for the live drawing relay (`relay/` at the repository root).
 * The relay checks the HMAC with the same secret and puts the socket in the couple's
 * room. Without a channel that is the widget canvas room. With one (`ch`), the socket
 * joins the room `<couple>:<channel>`, and the relay only accepts channels on its
 * allowlist. The ticket only has to last until the socket connects.
 * Returns null when the relay is not configured, so the app works without it.
 */
export async function signLiveTicket(args: {
  coupleId: string;
  userId: string;
  channel?: string;
}): Promise<{ url: string; ticket: string; expires_at: string } | null> {
  const url = process.env.PAEONIA_LIVE_RELAY_URL;
  const secret = process.env.PAEONIA_LIVE_RELAY_SECRET;
  if (!url || !secret) return null;
  const expiresAt = Date.now() + LIVE_TICKET_TTL_MS;
  const claims: Record<string, unknown> = { c: args.coupleId, u: args.userId, e: expiresAt };
  if (args.channel !== undefined) claims.ch = args.channel;
  const payload = btoa(JSON.stringify(claims)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return {
    url,
    ticket: `${payload}.${await hmacSha256Hex(secret, payload)}`,
    expires_at: new Date(expiresAt).toISOString(),
  };
}
