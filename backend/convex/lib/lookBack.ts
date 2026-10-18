import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent } from "./access";
import { getDailyAnswerDetails, type DailyAnswerDetailRow } from "./dailyAnswers";
import { QuestionContentReader, visibleAnswersOf } from "./dailyQuestions";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { addDaysToDate, endOfLocalDay, localDateOf, startOfLocalDay } from "./time";

/**
 * The Home look-back card: one old piece of the couple's shared history for the current couple day.
 * Three sources feed it. They are daily question rounds both partners answered, widget drawings,
 * and memories. Selection is a pure function of the couple id, the couple-local date, and the stored
 * data, so both partners get the same item all day and a refresh never changes it.
 */

/** Content must be at least this many whole days old. */
export const LOOK_BACK_MIN_AGE_DAYS = 7;
/** How many earlier years "on this day" checks. */
export const ON_THIS_DAY_YEARS = 5;
/** Candidates read per source when no "on this day" item exists. */
// ponytail: this takes the newest POOL_LIMIT items older than the minimum age from each source, so a couple with
// a long history sees mostly recent items on days without an "on this day" match. Page by a hashed date
// offset if that starts to feel repetitive.
export const POOL_LIMIT = 60;
/** Rows read per "on this day" date and source. */
const DAY_LIMIT = 20;
const EXCERPT_LENGTH = 200;

export type LookBackAnswer = {
  user_id: string;
  text: string | null;
  selected_user_id: string | null;
  has_photo: boolean;
  has_voice: boolean;
};

export type LookBackItem = {
  kind: "question" | "drawing" | "memory";
  /** The couple-local date the content belongs to (`YYYY-MM-DD`). */
  content_date: string;
  /** True when the content is from this month and day in an earlier year. */
  on_this_day: boolean;
  question: {
    instance_id: string;
    short_prompt_en: string;
    short_prompt_nb: string;
    own_answer: LookBackAnswer;
    partner_answer: LookBackAnswer;
  } | null;
  drawing: {
    revision_id: string;
    media_asset_id: string;
    author_user_id: string;
    canvas_side: number | null;
  } | null;
  memory: {
    memory_id: string;
    title: string;
    photo_media_asset_id: string | null;
  } | null;
};

/** A cheap pointer to content. `load` checks visibility and builds the item, or returns null when the content is not showable. */
type Candidate = {
  key: string;
  date: string;
  load: () => Promise<LookBackItem | null>;
};

type Frame = {
  ctx: ReaderCtx;
  userId: string;
  coupleId: string;
  today: string;
  timeZone: string;
  /** The newest content date that is old enough. */
  cutoffDate: string;
  /** Content created before this instant is old enough. */
  cutoffAt: string;
};

/** The same month and day `years` earlier, or null when it does not exist (29 February). */
export function sameDayYearsAgo(date: string, years: number): string | null {
  const year = Number(date.slice(0, 4)) - years;
  const candidate = `${String(year).padStart(4, "0")}${date.slice(4)}`;
  return addDaysToDate(candidate, 0) === candidate ? candidate : null;
}

export function isOnThisDay(contentDate: string, today: string): boolean {
  return contentDate < today && contentDate.slice(5) === today.slice(5);
}

/** FNV-1a. A small, stable hash. Nothing depends on its strength. */
export function hashString(value: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

/** The first item `load` produces, trying candidates in a fixed order that starts at `hash` modulo the count. */
async function firstShowable(candidates: Candidate[], hash: number, tried: Set<string>): Promise<LookBackItem | null> {
  const ordered = [...candidates].sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  for (let step = 0; step < ordered.length; step += 1) {
    const candidate = ordered[(hash + step) % ordered.length];
    if (tried.has(candidate.key)) continue;
    tried.add(candidate.key);
    const item = await candidate.load();
    if (item) return item;
  }
  return null;
}

/**
 * The one look-back item for `today` (the couple-local date), or null. Prefers content from this month and
 * day in an earlier year. The caller passes the viewer's couple, and this checks access again.
 */
export async function pickLookBack(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
  today: string,
  timeZone: string,
): Promise<LookBackItem | null> {
  if (!(await canAccessCoupleContent(ctx, userId, coupleId))) return null;
  const frame: Frame = {
    ctx,
    userId,
    coupleId,
    today,
    timeZone,
    cutoffDate: addDaysToDate(today, -LOOK_BACK_MIN_AGE_DAYS),
    cutoffAt: startOfLocalDay(addDaysToDate(today, -(LOOK_BACK_MIN_AGE_DAYS - 1)), timeZone),
  };
  const found = new Map<string, Candidate>();
  for (const list of [await questionCandidates(frame), await drawingCandidates(frame), await memoryCandidates(frame)]) {
    for (const candidate of list) found.set(candidate.key, candidate);
  }
  const all = [...found.values()];
  const hash = hashString(`${coupleId}:${today}`);
  const tried = new Set<string>();
  const onThisDay = all.filter((candidate) => isOnThisDay(candidate.date, today));
  return (await firstShowable(onThisDay, hash, tried)) ?? (await firstShowable(all, hash, tried));
}

/** The earlier dates with the same month and day, newest first. */
function onThisDayDates(frame: Frame): string[] {
  const dates: string[] = [];
  for (let years = 1; years <= ON_THIS_DAY_YEARS; years += 1) {
    const date = sameDayYearsAgo(frame.today, years);
    if (date) dates.push(date);
  }
  return dates;
}

// ---- daily question rounds ----

async function questionCandidates(frame: Frame): Promise<Candidate[]> {
  const { ctx } = frame;
  const instances = new Map<string, { instance: Doc<"daily_question_instances">; day: Doc<"couple_days"> }>();

  // The newest answers of each partner, so the pool is the same for both viewers. Each answer points at an
  // instance, and a round needs both partners' answers.
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", frame.coupleId).eq("status", "active"))
    .collect();
  for (const member of members) {
    const answers = await ctx.db
      .query("daily_question_answers")
      .withIndex("by_user_id_created_at", (q) => q.eq("user_id", member.user_id).lt("created_at", frame.cutoffAt))
      .order("desc")
      .take(POOL_LIMIT);
    for (const answer of answers) {
      if (instances.has(answer.instance_id)) continue;
      const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
      // A topic answer has no couple day and stays out of Look Back.
      const day = instance ? await getByUuid(ctx, "couple_days", instance.couple_day_id) : null;
      if (instance && day) instances.set(instance.id, { instance, day });
    }
  }

  // Every round asked on an "on this day" date.
  for (const date of onThisDayDates(frame)) {
    const day = await ctx.db
      .query("couple_days")
      .withIndex("by_couple_id_local_date", (q) => q.eq("couple_id", frame.coupleId).eq("local_date", date))
      .unique();
    if (!day) continue;
    const rows = await ctx.db
      .query("daily_question_instances")
      .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) => q.eq("couple_day_id", day.id))
      .take(DAY_LIMIT);
    for (const instance of rows) instances.set(instance.id, { instance, day });
  }

  const memberIds = members.map((member) => member.user_id);
  const reader = new QuestionContentReader(ctx);
  const candidates: Candidate[] = [];
  for (const { instance, day } of instances.values()) {
    if (day.couple_id !== frame.coupleId || instance.status === "shuffled" || day.local_date > frame.cutoffDate) continue;
    // Only rounds both partners answered count, so a one-sided question never takes a slot in the pick.
    const answered = new Set((await visibleAnswersOf(ctx, instance.id)).map((answer) => answer.user_id));
    if (!memberIds.every((id) => answered.has(id))) continue;
    candidates.push({
      key: `question:${instance.id}`,
      date: day.local_date,
      load: () => loadQuestion(frame, reader, instance, day),
    });
  }
  return candidates;
}

function excerpt(text: string | null): string | null {
  if (text === null) return null;
  const letters = Array.from(text);
  return letters.length <= EXCERPT_LENGTH ? text : letters.slice(0, EXCERPT_LENGTH).join("");
}

async function answerSummary(ctx: ReaderCtx, row: DailyAnswerDetailRow): Promise<LookBackAnswer> {
  let hasPhoto = false;
  let hasVoice = false;
  for (const assetId of row.media_asset_ids) {
    const asset = await getByUuid(ctx, "media_assets", assetId);
    if (asset?.media_type === "image") hasPhoto = true;
    if (asset?.media_type === "voice") hasVoice = true;
  }
  return {
    user_id: row.answer_user_id,
    text: excerpt(row.text_body),
    selected_user_id: row.selected_user_id,
    has_photo: hasPhoto,
    has_voice: hasVoice,
  };
}

/**
 * A round shows only when both people have a visible answer and the viewer may read both. The detail reader
 * applies the same reveal, moderation, and deleted-answer rules as the history screens.
 */
async function loadQuestion(
  frame: Frame,
  reader: QuestionContentReader,
  instance: Doc<"daily_question_instances">,
  day: Doc<"couple_days">,
): Promise<LookBackItem | null> {
  const content = await reader.get(instance.question_version_id);
  if (!content) return null;
  const rows = (await getDailyAnswerDetails(frame.ctx, frame.userId, day.id)).filter(
    (row) => row.instance_id === instance.id,
  );
  const own = rows.find((row) => row.answer_user_id === frame.userId);
  const partner = rows.find((row) => row.answer_user_id !== frame.userId);
  if (!own || !partner || !own.can_view_answer || !partner.can_view_answer) return null;
  return {
    kind: "question",
    content_date: day.local_date,
    on_this_day: isOnThisDay(day.local_date, frame.today),
    question: {
      instance_id: instance.id,
      short_prompt_en: content.en.short_prompt,
      short_prompt_nb: content.nb.short_prompt,
      own_answer: await answerSummary(frame.ctx, own),
      partner_answer: await answerSummary(frame.ctx, partner),
    },
    drawing: null,
    memory: null,
  };
}

// ---- widget drawings ----

async function drawingCandidates(frame: Frame): Promise<Candidate[]> {
  const { ctx } = frame;
  const canvas = await ctx.db
    .query("widget_canvases")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", frame.coupleId))
    .unique();
  if (!canvas || canvas.deleted_at !== undefined) return [];

  const revisions = new Map<string, Doc<"widget_drawing_revisions">>();
  const pool = await ctx.db
    .query("widget_drawing_revisions")
    .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvas.id).lt("created_at", frame.cutoffAt))
    .order("desc")
    .take(POOL_LIMIT);
  for (const revision of pool) revisions.set(revision.id, revision);
  for (const date of onThisDayDates(frame)) {
    const sameDay = await ctx.db
      .query("widget_drawing_revisions")
      .withIndex("by_canvas_id_created_at_id", (q) =>
        q
          .eq("canvas_id", canvas.id)
          .gte("created_at", startOfLocalDay(date, frame.timeZone))
          .lt("created_at", endOfLocalDay(date, frame.timeZone)),
      )
      .take(DAY_LIMIT);
    for (const revision of sameDay) revisions.set(revision.id, revision);
  }

  return [...revisions.values()].map((revision) => {
    const date = localDateOf(revision.created_at, frame.timeZone);
    return {
      key: `drawing:${revision.id}`,
      date,
      load: () => loadDrawing(frame, revision, date),
    };
  });
}

/** The same visibility rule as `payloadIsVisible` in `widget.ts`, which the drawing history uses. */
async function loadDrawing(
  frame: Frame,
  revision: Doc<"widget_drawing_revisions">,
  date: string,
): Promise<LookBackItem | null> {
  if (date > frame.cutoffDate || revision.deleted_at !== undefined || revision.moderation_status !== "visible") {
    return null;
  }
  const asset = await getByUuid(frame.ctx, "media_assets", revision.payload_media_asset_id);
  if (
    !asset ||
    asset.upload_status !== "finalized" ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    return null;
  }
  const side = (revision.bounds as { canvasSide?: unknown } | undefined | null)?.canvasSide;
  return {
    kind: "drawing",
    content_date: date,
    on_this_day: isOnThisDay(date, frame.today),
    question: null,
    drawing: {
      revision_id: revision.id,
      media_asset_id: asset.id,
      author_user_id: revision.author_user_id,
      canvas_side: typeof side === "number" && Number.isFinite(side) ? side : null,
    },
    memory: null,
  };
}

// ---- memories ----

async function memoryCandidates(frame: Frame): Promise<Candidate[]> {
  const { ctx } = frame;
  const memories = new Map<string, Doc<"memories">>();
  const pool = await ctx.db
    .query("memories")
    .withIndex("by_couple_id_memory_date_id", (q) => q.eq("couple_id", frame.coupleId).lte("memory_date", frame.cutoffDate))
    .order("desc")
    .take(POOL_LIMIT);
  for (const memory of pool) memories.set(memory.id, memory);
  for (const date of onThisDayDates(frame)) {
    const sameDay = await ctx.db
      .query("memories")
      .withIndex("by_couple_id_memory_date_id", (q) => q.eq("couple_id", frame.coupleId).eq("memory_date", date))
      .take(DAY_LIMIT);
    for (const memory of sameDay) memories.set(memory.id, memory);
  }
  return [...memories.values()].map((memory) => ({
    key: `memory:${memory.id}`,
    date: memory.memory_date,
    load: () => loadMemory(frame, memory),
  }));
}

/** The first photo that `get_memories` would list for the memory, in sort order. */
async function firstPhotoAssetId(ctx: ReaderCtx, memoryId: string): Promise<string | null> {
  const links = ctx.db
    .query("memory_media")
    .withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", memoryId))
    .order("asc");
  for await (const link of links) {
    if (link.deleted_at !== undefined || link.moderation_status !== "visible") continue;
    const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
    if (
      asset &&
      asset.media_type === "image" &&
      asset.reserved_parent_kind === "memory_media" &&
      asset.reserved_parent_id === link.id &&
      asset.upload_status === "finalized" &&
      asset.storage_delete_status === "none" &&
      asset.moderation_status === "visible" &&
      asset.deleted_at === undefined
    ) {
      return asset.id;
    }
  }
  return null;
}

async function loadMemory(frame: Frame, memory: Doc<"memories">): Promise<LookBackItem | null> {
  if (memory.memory_date > frame.cutoffDate || memory.deleted_at !== undefined || memory.moderation_status !== "visible") {
    return null;
  }
  return {
    kind: "memory",
    content_date: memory.memory_date,
    on_this_day: isOnThisDay(memory.memory_date, frame.today),
    question: null,
    drawing: null,
    memory: {
      memory_id: memory.id,
      title: memory.title,
      photo_media_asset_id: await firstPhotoAssetId(frame.ctx, memory.id),
    },
  };
}
