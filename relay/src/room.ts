/** What a room stores on each socket. `hasLeft` is set once the others were told it left. */
export type Attachment = { userId: string; socketId: string; closesAt: number; hasLeft?: boolean };

/** A socket must reconnect with a fresh ticket after this, so Convex checks access again. */
export const SESSION_MS = 10 * 60_000;

/** A socket past its session neither sends nor receives anything more. */
export function isExpired(attachment: Attachment, now: number): boolean {
  return now > attachment.closesAt;
}

/**
 * What a message from `senderUserId` does to one socket in the room. The sender's own sockets
 * and sockets that already left are skipped, and a socket past its session is closed instead of
 * hearing the message.
 */
export function deliveryFor(peer: Attachment, senderUserId: string, now: number): "send" | "expire" | "skip" {
  if (peer.userId === senderUserId || peer.hasLeft) return "skip";
  return isExpired(peer, now) ? "expire" : "send";
}

/** When the room's alarm should next close an expired socket, or null when no socket is open. */
export function nextExpiryAlarm(attachments: Attachment[]): number | null {
  const open = attachments.filter((attachment) => !attachment.hasLeft).map((attachment) => attachment.closesAt + 1);
  return open.length === 0 ? null : Math.min(...open);
}
