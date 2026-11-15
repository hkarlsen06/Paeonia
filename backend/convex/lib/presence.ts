import { Presence } from "@convex-dev/presence";
import { components } from "../_generated/api";
import type { ReaderCtx, WriterCtx } from "./db";
import type { GameKind } from "./games";
import type { ChatPlace } from "./threadSubjects";
import { GAME_KINDS } from "./validators";

// Who has the app open, who has a game screen open, who has a chat open and who is typing in
// it, kept by the @convex-dev/presence component. The component marks a user offline on its
// own once heartbeats stop, so no cron and no clock read in a query decides it.
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

/** The app open and in front on either partner's phone, one room per couple. */
export function appRoom(coupleId: string): string {
  return `${coupleId}:app`;
}

/** The couple's widget drawing screen open on either partner's phone, one room per couple. */
export function drawingRoom(coupleId: string): string {
  return `${coupleId}:drawing`;
}

/** Typing in one chat, named by its place, so a reader can tell which chat it is. */
export function chatTypingRoom(coupleId: string, place: ChatPlace): string {
  return `${typingRoomPrefix(coupleId)}${chatRoomKey(place)}`;
}

/** An open chat screen, named like its typing room. */
export function chatOpenRoom(coupleId: string, place: ChatPlace): string {
  return `${chatRoomPrefix(coupleId)}${chatRoomKey(place)}`;
}

const typingRoomPrefix = (coupleId: string) => `${coupleId}:typing:`;
const chatRoomPrefix = (coupleId: string) => `${coupleId}:chat:`;

/** The chat's kind, then its game or its subject's id. `chatPlaceOfRoomKey` reads it back. */
function chatRoomKey(place: ChatPlace): string {
  switch (place.kind) {
    case "couple":
      return "couple";
    case "game":
      return `game:${place.game_kind}`;
    case "daily_question":
      return `daily_question:${place.daily_question_id}`;
    case "memory":
      return `memory:${place.memory_id}`;
    case "story":
      return `story:${place.story_id}`;
  }
}

function chatPlaceOfRoomKey(key: string): ChatPlace | null {
  if (key === "couple") return { kind: "couple" };
  const separator = key.indexOf(":");
  if (separator < 0) return null;
  const id = key.slice(separator + 1);
  switch (key.slice(0, separator)) {
    case "game": {
      const game = GAME_KINDS.find((kind) => kind === id);
      return game === undefined ? null : { kind: "game", game_kind: game };
    }
    case "daily_question":
      return { kind: "daily_question", daily_question_id: id };
    case "memory":
      return { kind: "memory", memory_id: id };
    case "story":
      return { kind: "story", story_id: id };
    default:
      return null;
  }
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

/** True while the user has the game screen open. */
export async function isGamePresent(ctx: ReaderCtx, coupleId: string, kind: GameKind, userId: string): Promise<boolean> {
  return (await onlineUserIds(ctx, gameRoom(coupleId, kind))).includes(userId);
}

/** The game kinds a user has open in a couple's rooms. One read for all kinds, where `onlineUserIds` reads one room. */
export async function openGameKinds(ctx: ReaderCtx, coupleId: string, userId: string): Promise<Set<string>> {
  const prefix = gameRoomPrefix(coupleId);
  const rooms = await presence.listUser(ctx, userId, true, 1000);
  return new Set(rooms.filter(({ roomId }) => roomId.startsWith(prefix)).map(({ roomId }) => roomId.slice(prefix.length)));
}

/**
 * Where a partner is in the app: the game screens they have open, whether they have the drawing
 * open, a chat screen and the chat they type in.
 */
export type PartnerPlaces = { games: GameKind[]; drawing: boolean; chat: ChatPlace | null; typing: ChatPlace | null };

/**
 * Where the user is in the couple's rooms, from one read of their online rooms, or null while
 * they are not in the app room. Open games come in `GAME_KINDS` order, and the app keeps the
 * order they opened in. Several open chats name the first room id, so every read picks the same one.
 */
export async function placesInApp(ctx: ReaderCtx, coupleId: string, userId: string): Promise<PartnerPlaces | null> {
  const prefix = `${coupleId}:`;
  const rooms = (await presence.listUser(ctx, userId, true, 1000))
    .map(({ roomId }) => roomId)
    .filter((roomId) => roomId.startsWith(prefix))
    .sort();
  if (!rooms.includes(appRoom(coupleId))) return null;
  const keysAfter = (roomPrefix: string) =>
    rooms.filter((roomId) => roomId.startsWith(roomPrefix)).map((roomId) => roomId.slice(roomPrefix.length));
  const firstPlace = (keys: string[]) => keys.map(chatPlaceOfRoomKey).find((place) => place !== null) ?? null;
  const games = new Set(keysAfter(gameRoomPrefix(coupleId)));
  return {
    games: GAME_KINDS.filter((kind) => games.has(kind)),
    drawing: rooms.includes(drawingRoom(coupleId)),
    chat: firstPlace(keysAfter(chatRoomPrefix(coupleId))),
    typing: firstPlace(keysAfter(typingRoomPrefix(coupleId))),
  };
}

/**
 * Removes every presence room these users are in whose id starts with `prefix`, for all
 * members of the room. Pass a couple id when the relationship ends, or "" to clear everything
 * of a deleted account.
 */
export async function removePresenceRooms(ctx: WriterCtx, userIds: string[], prefix: string): Promise<void> {
  for (const userId of userIds) {
    let limit = 1000;
    while (true) {
      const rooms = await presence.listUser(ctx, userId, false, limit);
      const matching = rooms.filter(({ roomId }) => roomId.startsWith(prefix));
      for (const { roomId } of matching) await presence.removeRoom(ctx, roomId);
      if (rooms.length < limit) break;
      // The component has no cursor. Grow past unrelated rooms without removing them.
      if (matching.length === 0) limit += 1000;
    }
  }
}
