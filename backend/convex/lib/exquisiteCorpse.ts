import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull } from "./db";
import { fail, uniqueViolation } from "./errors";
import { EXQUISITE_CORPSE_IDEAS, type Idea, type IdeaLanguage, type IdeaPart } from "./exquisiteCorpseIdeas";
import type { GameBackend } from "./gameRegistry";
import { enqueueGamePush, TURN_REMINDER_AFTER_MS } from "./games";
import { uuidArg } from "./ids";
import { addMs, nowIso } from "./time";

// Exquisite corpse: the rules, the json shapes, the media hooks, and the hooks the shared games code
// calls (`exquisiteCorpseBackend` at the end). The registered functions are in convex/exquisiteCorpse.ts.
// The design is in docs/games/exquisite-corpse.md. The first half of this file needs no database.

export type CorpseGame = Doc<"exquisite_corpse_games">;
export type CorpseFigure = Doc<"exquisite_corpse_figures">;
export type CorpsePart = Doc<"exquisite_corpse_parts">;

/** The parts of a figure in drawing order. The index is the part's `part_index`. */
export const PART_NAMES = ["head", "body", "legs"] as const satisfies readonly IdeaPart[];
const LEGS_INDEX = 2;
/** How many ideas the server deals for one part. */
export const DECK_SIZE = 12;
/** The finished figures `get_exquisite_corpse` returns. */
export const RECENT_FIGURES = 10;
/** The most figures one history page returns. */
export const MAX_HISTORY_PAGE = 50;

// --- Rules (no database) ----------------------------------------------------

export function isPartIndex(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= LEGS_INDEX;
}

/** The head and the body leave a strip for the next drawer. The legs leave none. */
export function hasStrip(partIndex: number): boolean {
  return partIndex < LEGS_INDEX;
}

/**
 * The step token of the turn push after part `partIndex` (0 or 1): the part that is now the
 * partner's turn. The push copy turns "body" into "Robin drew the head" and "Your turn to draw the body."
 */
export function turnPushPart(partIndex: number): IdeaPart {
  return PART_NAMES[partIndex + 1];
}

/**
 * The game's progress once part `partIndex` of figure `figureId` is sent. The legs finish the
 * figure, clear `figure_id`, and the next figure starts with the head.
 */
export function progressAfter(
  game: Pick<CorpseGame, "figure_number" | "figures_finished">,
  partIndex: number,
  figureId: string,
) {
  const figureFinished = partIndex === LEGS_INDEX;
  return {
    figureFinished,
    figure_id: figureFinished ? undefined : figureId,
    figure_number: figureFinished ? game.figure_number + 1 : game.figure_number,
    part_index: figureFinished ? 0 : partIndex + 1,
    figures_finished: figureFinished ? game.figures_finished + 1 : game.figures_finished,
  };
}

/** A small seeded generator (xmur3 hash into mulberry32). The same seed gives the same numbers in [0, 1). */
export function seededRandom(seed: string): () => number {
  let hash = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) {
    hash = Math.imul(hash ^ seed.charCodeAt(i), 3432918353);
    hash = (hash << 13) | (hash >>> 19);
  }
  hash = Math.imul(hash ^ (hash >>> 16), 2246822507);
  hash = Math.imul(hash ^ (hash >>> 13), 3266489909);
  let state = (hash ^ (hash >>> 16)) >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), state | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The first `size` ideas of a seeded shuffle (Fisher-Yates). Does not change `ideas`. */
export function shuffledDeck(ideas: readonly Idea[], seed: string, size = DECK_SIZE): Idea[] {
  const random = seededRandom(seed);
  const deck = [...ideas];
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck.slice(0, size);
}

/** The seed of the deck for the game's next part. Reopening the game deals the same deck. */
export function deckSeed(game: Pick<CorpseGame, "id" | "figure_number" | "part_index">): string {
  return `${game.id}:${game.figure_number}:${game.part_index}`;
}

/** The deck for a part in a language. */
export function dealIdeas(language: IdeaLanguage, partIndex: number, seed: string): Idea[] {
  return shuffledDeck(EXQUISITE_CORPSE_IDEAS[language][PART_NAMES[partIndex]], seed);
}

/**
 * The idea with this id in the part's list. Either language's list counts, because a phone may send an
 * idea dealt before the couple changed the game language. `preferred` wins when both lists have the id.
 */
export function findIdea(
  partIndex: number,
  ideaId: string,
  preferred: IdeaLanguage,
  lists: Record<IdeaLanguage, Record<IdeaPart, readonly Idea[]>> = EXQUISITE_CORPSE_IDEAS,
): Idea | null {
  const other: IdeaLanguage = preferred === "en" ? "nb" : "en";
  for (const language of [preferred, other]) {
    const found = lists[language][PART_NAMES[partIndex]].find((idea) => idea.id === ideaId);
    if (found) return found;
  }
  return null;
}

/** Whether `userId` may see the part's full drawing and its idea: its drawer, or anyone once the figure is finished. */
export function canSeePartContent(part: Pick<CorpsePart, "drawer_user_id">, userId: string, figureFinished: boolean): boolean {
  return figureFinished || part.drawer_user_id === userId;
}

/** The reveal seen time of `userId`: the starter's own field, or the partner's. */
export function revealSeenAt(
  figure: Pick<CorpseFigure, "starter_user_id" | "starter_reveal_seen_at" | "partner_reveal_seen_at">,
  userId: string,
): string | undefined {
  return figure.starter_user_id === userId ? figure.starter_reveal_seen_at : figure.partner_reveal_seen_at;
}

/**
 * One part for `userId`. The full drawing and the idea stay null until the caller drew the part or the
 * figure is finished, so a hidden part never reaches the partner's phone. The strip is always there for
 * the head and body.
 */
export function partJson(
  part: Pick<
    CorpsePart,
    "id" | "part_index" | "drawer_user_id" | "created_at" | "strip_media_asset_id" | "drawing_media_asset_id" | "idea_id" | "idea_text"
  >,
  userId: string,
  figureFinished: boolean,
) {
  const visible = canSeePartContent(part, userId, figureFinished);
  return {
    id: part.id,
    part_index: part.part_index,
    drawer_user_id: part.drawer_user_id,
    created_at: part.created_at,
    strip_media_asset_id: orNull(part.strip_media_asset_id),
    drawing_media_asset_id: visible ? part.drawing_media_asset_id : null,
    idea: visible && part.idea_id !== undefined && part.idea_text !== undefined ? { id: part.idea_id, text: part.idea_text } : null,
  };
}

// --- Lookups and json -------------------------------------------------------

export async function getCorpseGame(ctx: ReaderCtx, coupleId: string): Promise<CorpseGame | null> {
  return await ctx.db
    .query("exquisite_corpse_games")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

/** Patches a game row and bumps `version`. */
export async function patchCorpseGame(
  ctx: WriterCtx,
  game: CorpseGame,
  patch: Partial<Omit<CorpseGame, "_id" | "_creationTime">>,
): Promise<void> {
  await ctx.db.patch(game._id, { ...patch, version: game.version + 1, updated_at: nowIso() });
}

/** The user's star on a figure, if any. */
export async function getFigureStar(ctx: ReaderCtx, figureId: string, userId: string): Promise<Doc<"exquisite_corpse_stars"> | null> {
  return await ctx.db
    .query("exquisite_corpse_stars")
    .withIndex("by_user_id_figure_id", (q) => q.eq("user_id", userId).eq("figure_id", figureId))
    .unique();
}

export function corpseGameJson(game: CorpseGame) {
  return {
    id: game.id,
    turn_user_id: game.turn_user_id,
    turn_started_at: game.turn_started_at,
    figure_id: orNull(game.figure_id),
    figure_number: game.figure_number,
    part_index: game.part_index,
    figures_finished: game.figures_finished,
    version: game.version,
    created_at: game.created_at,
    updated_at: game.updated_at,
  };
}

/** One figure with its parts for `userId`, including the caller's own star. See `partJson` for what stays hidden. */
export async function figureJson(ctx: ReaderCtx, figure: CorpseFigure, userId: string) {
  const parts = await ctx.db
    .query("exquisite_corpse_parts")
    .withIndex("by_figure_id_part_index", (q) => q.eq("figure_id", figure.id))
    .collect();
  const finished = figure.finished_at !== undefined;
  return {
    id: figure.id,
    number: figure.number,
    starter_user_id: figure.starter_user_id,
    created_at: figure.created_at,
    finished_at: orNull(figure.finished_at),
    my_reveal_seen_at: orNull(revealSeenAt(figure, userId)),
    starred_by_me: (await getFigureStar(ctx, figure.id, userId)) !== null,
    parts: parts.map((part) => partJson(part, userId, finished)),
  };
}

// --- Media ------------------------------------------------------------------

type PartPurpose = "exquisite_corpse_drawing" | "exquisite_corpse_strip";

export function isCorpseUploadPurpose(purpose: string): purpose is PartPurpose {
  return purpose === "exquisite_corpse_drawing" || purpose === "exquisite_corpse_strip";
}

/**
 * Checks a reservation for a part's drawing or strip and returns the storage path. The caller needs
 * couple access, and the couple must own the game named in the path context. The part does not exist
 * yet: the phone makes its id up front.
 */
export async function reserveCorpseUpload(
  ctx: ReaderCtx,
  args: {
    userId: string;
    kind: string;
    mediaType: string;
    coupleId: string | undefined;
    pathContext: Record<string, unknown>;
    partId: string;
    assetId: string;
    extension: string;
  },
): Promise<string> {
  const { coupleId, pathContext } = args;
  if (args.kind !== "exquisite_corpse_part" || args.mediaType !== "drawing_payload" || coupleId === undefined) {
    return fail("23514", "exquisite corpse upload contract is invalid");
  }
  if (!(await canAccessCoupleContent(ctx, args.userId, coupleId))) {
    return fail("42501", "active entitled couple access is required");
  }
  const rawGameId = pathContext.game_id;
  if (rawGameId === undefined || rawGameId === null || rawGameId === "") {
    return fail("23514", "exquisite corpse uploads require a game id");
  }
  const gameId = uuidArg(rawGameId);
  const game = await getByUuid(ctx, "exquisite_corpse_games", gameId);
  if (!game || game.couple_id !== coupleId) return fail("42501", "active entitled game access is required");
  return `${coupleId}/${gameId}/parts/${args.partId}/${args.assetId}.${args.extension}`;
}

/** The finished upload as a usable asset of this part, owned by `userId`, and not used by another part. */
export async function assertCorpseAssetUsable(
  ctx: ReaderCtx,
  userId: string,
  part: { id: string; couple_id: string; game_id: string },
  assetId: string,
  purpose: PartPurpose,
): Promise<void> {
  const label = purpose === "exquisite_corpse_drawing" ? "drawing" : "strip";
  const asset = await getByUuid(ctx, "media_assets", assetId);
  if (
    !asset ||
    asset.owner_user_id !== userId ||
    asset.couple_id !== part.couple_id ||
    asset.bucket !== "game-drawings" ||
    asset.expected_bucket !== "game-drawings" ||
    asset.reserved_parent_kind !== "exquisite_corpse_part" ||
    asset.reserved_parent_id !== part.id ||
    asset.upload_purpose !== purpose ||
    asset.media_type !== "drawing_payload" ||
    asset.expected_media_type !== "drawing_payload" ||
    !asset.storage_path.startsWith(`${part.couple_id}/${part.game_id}/parts/${part.id}/`) ||
    asset.upload_status !== "finalized" ||
    asset.upload_finalized_at === undefined ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", `exquisite corpse ${label} asset is not usable`);
  }
  const taken =
    purpose === "exquisite_corpse_drawing"
      ? await ctx.db.query("exquisite_corpse_parts").withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing_media_asset_id", assetId)).first()
      : await ctx.db.query("exquisite_corpse_parts").withIndex("by_strip_media_asset_id", (q) => q.eq("strip_media_asset_id", assetId)).first();
  if (taken) uniqueViolation(`exquisite_corpse_parts_${label}_media_asset_id_unique_idx`);
}

/**
 * Whether `userId` may read the asset of a sent part. Any member of the couple reads a strip at once.
 * The full drawing is for its drawer, and for both partners once the figure is finished.
 */
export async function canReadCorpseAsset(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  if (asset.couple_id === undefined || !(await canAccessCoupleContent(ctx, userId, asset.couple_id))) return false;
  const isStrip = asset.upload_purpose === "exquisite_corpse_strip";
  const part = isStrip
    ? await ctx.db.query("exquisite_corpse_parts").withIndex("by_strip_media_asset_id", (q) => q.eq("strip_media_asset_id", asset.id)).first()
    : await ctx.db.query("exquisite_corpse_parts").withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing_media_asset_id", asset.id)).first();
  if (!part || part.id !== asset.reserved_parent_id || part.couple_id !== asset.couple_id) return false;
  if (isStrip) return true;
  const figure = await getByUuid(ctx, "exquisite_corpse_figures", part.figure_id);
  return figure !== null && canSeePartContent(part, userId, figure.finished_at !== undefined);
}

/**
 * The step token of a reminder: the turn it is for, as the figure number and the part. It has no
 * copy of its own, so the push shows the usual reminder, and it tells an old reminder from the
 * reminder of a later turn of the same person.
 */
export function reminderStep(game: Pick<CorpseGame, "figure_number" | "part_index">): string {
  return `turn_${game.figure_number}_${game.part_index}`;
}

// --- What the shared games code asks of Exquisite corpse --------------------

/**
 * Registered in `GAME_BACKENDS` (gameRegistry.ts). Deleting the couple's rows leaves the drawing media
 * to the couple media sweep in `cleanupCoupleContent`.
 */
export const exquisiteCorpseBackend: GameBackend = {
  /**
   * `payload.round_id` is the figure id. A turn push is wanted while the turn is still the recipient's in
   * that figure. Turns alternate and a figure ends after the legs, so the turn leaves the recipient once
   * they send their part. A result push is wanted until the recipient has seen the reveal. A reminder
   * is wanted while the reminded turn still waits (a new turn clears `turn_reminder_sent_at`).
   */
  async pushStillWanted(ctx, push, payload, recipientUserId) {
    const figureId = typeof payload.round_id === "string" ? payload.round_id : null;
    const gameId = typeof payload.game_id === "string" ? payload.game_id : null;
    const game = gameId ? await getByUuid(ctx, "exquisite_corpse_games", gameId) : null;
    switch (push) {
      case "game_turn_ready":
        return game !== null && game.turn_user_id === recipientUserId && figureId !== null && game.figure_id === figureId;
      case "game_result": {
        const figure = figureId ? await getByUuid(ctx, "exquisite_corpse_figures", figureId) : null;
        return (
          figure !== null &&
          figure.couple_id === payload.couple_id &&
          figure.finished_at !== undefined &&
          revealSeenAt(figure, recipientUserId) === undefined
        );
      }
      case "game_turn_reminder":
        return (
          game !== null &&
          game.turn_user_id === recipientUserId &&
          game.turn_reminder_sent_at !== undefined &&
          payload.step === reminderStep(game)
        );
      case "game_invite":
        return true;
    }
  },

  /** The couple's one game, when it is the user's turn or the newest finished figure's reveal is unseen by them. */
  async waitingFor(ctx, coupleId, userId) {
    const game = await getCorpseGame(ctx, coupleId);
    if (!game) return 0;
    if (game.turn_user_id === userId) return 1;
    const finished = await ctx.db
      .query("exquisite_corpse_figures")
      .withIndex("by_game_id_number", (q) => q.eq("game_id", game.id))
      .order("desc")
      .filter((q) => q.neq(q.field("finished_at"), undefined))
      .first();
    return finished !== null && revealSeenAt(finished, userId) === undefined ? 1 : 0;
  },

  async deleteCoupleRows(ctx, coupleId) {
    let deleted = 0;
    const remove = async (row: { _id: Parameters<WriterCtx["db"]["delete"]>[0] }) => {
      await ctx.db.delete(row._id);
      deleted += 1;
    };
    for (const row of await ctx.db.query("exquisite_corpse_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
    for (const row of await ctx.db.query("exquisite_corpse_figures").withIndex("by_couple_id_number", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
    for (const row of await ctx.db.query("exquisite_corpse_parts").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
    for (const row of await ctx.db.query("exquisite_corpse_stars").withIndex("by_couple_id_user_id_figure_number", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
    return deleted;
  },

  /**
   * The single reminder for a turn that waited 72 hours. `turn_reminder_sent_at` is set before anything
   * else and cleared only when a new turn begins, so a turn never gets two reminders.
   */
  async sendDueTurnReminders(ctx, now) {
    const due = await ctx.db
      .query("exquisite_corpse_games")
      .withIndex("by_turn_reminder_sent_at_turn_started_at", (q) =>
        q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS)),
      )
      .take(100);
    let sent = 0;
    for (const game of due) {
      await ctx.db.patch(game._id, { turn_reminder_sent_at: now });
      if (!(await canAccessCoupleContent(ctx, game.turn_user_id, game.couple_id))) continue;
      const waiting = (await listActiveMembers(ctx, game.couple_id)).find((member) => member.user_id !== game.turn_user_id);
      sent += await enqueueGamePush(ctx, {
        kind: "game_turn_reminder",
        game_kind: "exquisite_corpse",
        couple_id: game.couple_id,
        game_id: game.id,
        actor_user_id: waiting?.user_id ?? game.turn_user_id,
        recipient_user_id: game.turn_user_id,
        dedupe_key: `exquisite_corpse:reminder:${game.id}:${game.turn_started_at}`,
        step: reminderStep(game),
      });
    }
    return sent;
  },
};
