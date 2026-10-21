import { Presence } from "@convex-dev/presence";
import { components } from "../_generated/api";
import type { ReaderCtx, WriterCtx } from "./db";
import type { GameKind } from "./games";

// Who has a game screen open and who is typing in a chat, kept by the
// @convex-dev/presence component. The component marks a user offline on its own once
// heartbeats stop, so no cron and no clock read in a query decides it.
//
// Only server code calls the component. The caller checks couple access first and passes
// a room built here from the couple id, so a client never names a room or a user. Every
// room id starts with the couple id, which is how relationship cleanup finds them.

const presence = new Presence(components.presence);

/** The open game screen of either partner, one room per couple and game. */
export function gameRoom(coupleId: string, kind: GameKind): string {
  return `${gameRoomPrefix(coupleId)}${kind}`;
}

const gameRoomPrefix = (coupleId: string) => `${coupleId}:game:`;

/** Typing in one chat, named by its subject's id (a question, a memory or a story). */
export function chatTypingRoom(coupleId: string, subjectId: string): string {
  return `${coupleId}:typing:${subjectId}`;
}

/**
 * A heartbeat (`present` true) or leaving the room (`present` false). Each user has one
 * session per room, so leaving from one phone clears the user in that room. Without another
 * heartbeat the component marks the user offline `timeoutMs` after this one.
 */
export async function setPresent(
  ctx: WriterCtx,
  roomId: string,
  userId: string,
  present: boolean,
  timeoutMs: number,
): Promise<void> {
  if (present) {
    // The component times a session out 2.5 heartbeat intervals after the last heartbeat.
    await presence.heartbeat(ctx, roomId, userId, `${roomId}:${userId}`, timeoutMs / 2.5);
  } else if ((await presence.listRoom(ctx, roomId)).some((row) => row.userId === userId)) {
    await presence.removeRoomUser(ctx, roomId, userId);
  }
}

/** The users online in a room. Reads no clock, so queries may call it. */
export async function onlineUserIds(ctx: ReaderCtx, roomId: string): Promise<string[]> {
  return (await presence.listRoom(ctx, roomId, true)).map((row) => row.userId);
}

/** The game kinds a user has open in a couple's rooms. One read for all kinds, where `onlineUserIds` reads one room. */
export async function openGameKinds(ctx: ReaderCtx, coupleId: string, userId: string): Promise<Set<string>> {
  const prefix = gameRoomPrefix(coupleId);
  const rooms = await presence.listUser(ctx, userId, true, 1000);
  return new Set(rooms.filter(({ roomId }) => roomId.startsWith(prefix)).map(({ roomId }) => roomId.slice(prefix.length)));
}

/**
 * Removes every presence room these users are in whose id starts with `prefix`, for all
 * members of the room. Pass a couple id when the relationship ends, or "" to clear everything
 * of a deleted account.
 */
export async function removePresenceRooms(ctx: WriterCtx, userIds: string[], prefix: string): Promise<void> {
  const rooms = new Set<string>();
  for (const userId of userIds) {
    // ponytail: one page of 1000 rooms per user. A user has at most one room per game and
    // couple, plus typing rooms an app left behind when it was killed mid-typing.
    for (const { roomId } of await presence.listUser(ctx, userId, false, 1000)) {
      if (roomId.startsWith(prefix)) rooms.add(roomId);
    }
  }
  for (const roomId of rooms) await presence.removeRoom(ctx, roomId);
}
