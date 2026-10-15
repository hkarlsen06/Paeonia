/** What a room stores on each socket. `hasLeft` is set once the others were told it left. */
export type Attachment = { userId: string; socketId: string; openedAt: number; closesAt: number; hasLeft?: boolean };

/** A socket must reconnect with a fresh ticket after this, so Convex checks access again. */
export const SESSION_MS = 10 * 60_000;

export const MAX_SOCKETS_PER_ROOM = 4;
export const MAX_MESSAGE_BYTES = 4 * 1_048_576;

/** A socket younger than this is never replaced, so two surfaces of one user cannot push each other out in a loop. */
export const MIN_REPLACE_AGE_MS = 10_000;

/** True when a message is over `MAX_MESSAGE_BYTES`. A string counts in UTF-8 bytes, not in UTF-16 units. */
export function isTooLarge(message: string | ArrayBuffer): boolean {
  if (typeof message !== "string") return message.byteLength > MAX_MESSAGE_BYTES;
  // A UTF-16 unit is at most 3 UTF-8 bytes, so only a long string needs counting.
  return message.length * 3 > MAX_MESSAGE_BYTES && new TextEncoder().encode(message).length > MAX_MESSAGE_BYTES;
}

/**
 * The socket a full room closes to make space for a new connection of `userId`: that user's oldest
 * open socket, as long as it is at least `MIN_REPLACE_AGE_MS` old. A phone that lost its connection
 * leaves a half-open socket behind that nothing closes for up to 10 minutes, and without this its
 * reconnects would be refused until then. Null when the user has no socket old enough.
 */
export function socketToReplace(attachments: Attachment[], userId: string, now: number): string | null {
  const oldest = attachments
    .filter((attachment) => attachment.userId === userId && !attachment.hasLeft)
    .reduce<Attachment | null>((best, attachment) => (best === null || attachment.openedAt < best.openedAt ? attachment : best), null);
  return oldest !== null && now - oldest.openedAt >= MIN_REPLACE_AGE_MS ? oldest.socketId : null;
}

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
