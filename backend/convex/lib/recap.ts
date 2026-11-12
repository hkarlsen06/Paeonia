import type { Doc, Id } from "../_generated/dataModel";
import { listActiveMembers } from "./access";
import { daysBetweenDates, dateInYear } from "./coupleDates";
import { isVisibleAnswer } from "./dailyQuestions";
import { getByUuid, type ReaderCtx, type WriterCtx } from "./db";
import { hashString, type LookBackRef } from "./lookBack";
import { addDaysToDate, localDateOf, nowIso, parseDate, startOfLocalDay } from "./time";

// Every count is something both partners can already see, so the shared row tells neither of them
// anything new: a round counts only when both answered, a letter only once it arrived, and nothing
// deleted or hidden counts. Days together come from planned visits, because `together_days` keeps
// 45 days.

const RECAP_SHOWN_DAYS = 14;
const RECAP_MIN_DAYS = 14;
const MAX_HIGHLIGHTS = 3;

// A counting call reads whole sources while they fit in a page, and pages through at most one source
// that does not, since Convex allows one `.paginate` per function. It stops before CALL_READS.
const PAGE = 400;
const CALL_READS = 1_000;

export type RecapPeriod = {
  anniversary_date: string;
  years: number;
  period_start: string;
  period_end: string;
  since_joined: boolean;
};

export function recapPeriod(startedOn: string, coupleCreatedOn: string, today: string): RecapPeriod | null {
  const [startYear] = parseDate(startedOn);
  const [todayYear] = parseDate(today);
  let year = todayYear;
  if (dateInYear(startedOn, year) > today) year -= 1;
  const years = year - startYear;
  if (years < 1) return null;
  const anniversary = dateInYear(startedOn, year);
  const previous = dateInYear(startedOn, year - 1);
  const start = coupleCreatedOn > previous ? coupleCreatedOn : previous;
  if (daysBetweenDates(start, anniversary) < RECAP_MIN_DAYS) return null;
  return { anniversary_date: anniversary, years, period_start: start, period_end: anniversary, since_joined: start !== previous };
}

export function isRecapShown(anniversary: string, today: string): boolean {
  const days = daysBetweenDates(anniversary, today);
  return days >= 0 && days < RECAP_SHOWN_DAYS;
}

/** The period of the recap due on the couple's `today`, or null when none is due. */
export function dueRecapPeriod(couple: Doc<"couples">, today: string, timeZone: string): RecapPeriod | null {
  if (!couple.started_on || couple.status !== "active") return null;
  const period = recapPeriod(couple.started_on, localDateOf(couple.created_at, timeZone), today);
  return period && isRecapShown(period.anniversary_date, today) ? period : null;
}

type Counting = NonNullable<Doc<"anniversary_recaps">["counting"]>;

/** Picks up to three moments, taking turns between memories (with a photo first), rounds and drawings. */
export function pickHighlights(candidates: {
  photoMemories: string[];
  memories: string[];
  questions: string[];
  drawings: string[];
}): LookBackRef[] {
  const queues: LookBackRef[][] = [
    [...candidates.photoMemories, ...candidates.memories].map((id) => ({ kind: "memory", id })),
    candidates.questions.map((id) => ({ kind: "question", id })),
    candidates.drawings.map((id) => ({ kind: "drawing", id })),
  ];
  const picked: LookBackRef[] = [];
  while (picked.length < MAX_HIGHLIGHTS && queues.some((queue) => queue.length > 0)) {
    for (const queue of queues) {
      const next = queue.shift();
      if (next && picked.length < MAX_HIGHLIGHTS) picked.push(next);
    }
  }
  return picked;
}

export async function findRecap(
  ctx: ReaderCtx,
  coupleId: string,
  anniversaryDate: string,
): Promise<Doc<"anniversary_recaps"> | null> {
  return await ctx.db
    .query("anniversary_recaps")
    .withIndex("by_couple_id_anniversary_date", (q) => q.eq("couple_id", coupleId).eq("anniversary_date", anniversaryDate))
    .unique();
}

/** Deletes every recap of the couple. They are worked out from the start date, so a new one goes with them. */
export async function deleteCoupleRecaps(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = await ctx.db
    .query("anniversary_recaps")
    .withIndex("by_couple_id_anniversary_date", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}

/**
 * The recap due on the couple's `today`: the stored row, or a new row that `countRecapStep` still
 * has to count. Null when none is due or the partner has left.
 */
export async function startRecap(
  ctx: WriterCtx,
  coupleId: string,
  today: string,
  timeZone: string,
): Promise<Doc<"anniversary_recaps"> | null> {
  const couple = await getByUuid(ctx, "couples", coupleId);
  const period = couple ? dueRecapPeriod(couple, today, timeZone) : null;
  if (!period) return null;
  const existing = await findRecap(ctx, coupleId, period.anniversary_date);
  if (existing) return existing;
  const members = await listActiveMembers(ctx, coupleId);
  if (members.length < 2) return null;
  const id = await ctx.db.insert("anniversary_recaps", {
    couple_id: coupleId,
    ...period,
    counts: {
      answered_together: 0,
      drawings: 0,
      memories: 0,
      memory_photos: 0,
      stories: 0,
      letters: 0,
      visits: 0,
      visit_days: 0,
      game_days: 0,
      longest_streak_all_time: 0,
    },
    hearts_sent: [],
    counted_on: today,
    highlights: [],
    counting: {
      member_ids: members.map((member) => member.user_id),
      time_zone: timeZone,
      source: 0,
      cursor: null,
      answered: [],
      answered_by_both: [],
      memories: [],
      visits: [],
      questions: [],
      drawings: [],
    },
    created_at: nowIso(),
  });
  return await ctx.db.get(id);
}

type Step = {
  ctx: WriterCtx;
  recap: Doc<"anniversary_recaps">;
  counting: Counting;
  counts: Doc<"anniversary_recaps">["counts"];
  startAt: string;
  endAt: string;
};

/** The part of a Convex query a source needs: an index range, read whole or a page at a time. */
type Rows<T> = {
  take(n: number): Promise<T[]>;
  paginate(options: { numItems: number; cursor: string | null }): Promise<{
    page: T[];
    isDone: boolean;
    continueCursor: string;
  }>;
};

type Source<T> = {
  /** The rows to read, or null when there are none. */
  rows: (step: Step) => Promise<Rows<T> | null>;
  /** Adds one batch of rows to the counts. Batches come in index order. */
  add: (step: Step, rows: T[]) => void;
};

const source = <T>(spec: Source<T>): Source<unknown> => spec as Source<unknown>;

/** Ranks ids by a hash of the recap and the id, so the picked moments are the same on every run. */
function rankBy(recap: Doc<"anniversary_recaps">) {
  const rank = (id: string) => hashString(`${recap.couple_id}:${recap.anniversary_date}:${id}`);
  return (ids: string[]) => [...ids].sort((a, b) => rank(a) - rank(b)).slice(0, MAX_HIGHLIGHTS);
}

function answersOf(member: number, add: (step: Step, instanceIds: string[]) => void) {
  return source<Doc<"daily_question_answers">>({
    rows: async ({ ctx, counting, startAt, endAt }) =>
      ctx.db
        .query("daily_question_answers")
        .withIndex("by_user_id_created_at", (q) =>
          q.eq("user_id", counting.member_ids[member]).gte("created_at", startAt).lt("created_at", endAt)),
    add: (step, answers) => add(step, answers.filter((answer) => isVisibleAnswer(answer)).map((answer) => answer.instance_id)),
  });
}

function photosOf(member: number) {
  return source<Doc<"memory_media">>({
    rows: async ({ ctx, counting }) =>
      ctx.db
        .query("memory_media")
        .withIndex("by_owner_user_id_memory_id", (q) => q.eq("owner_user_id", counting.member_ids[member])),
    add: ({ counting }, photos) => {
      const index = new Map(counting.memories.map((memory, at) => [memory.id, at]));
      for (const photo of photos) {
        const at = index.get(photo.memory_id);
        if (at === undefined || photo.deleted_at !== undefined || photo.moderation_status !== "visible") continue;
        counting.memories[at].photos += 1;
      }
    },
  });
}

function lettersTo(member: number) {
  return source<Doc<"letters">>({
    rows: async ({ ctx, counting, recap, startAt, endAt }) =>
      ctx.db
        .query("letters")
        .withIndex("by_couple_id_recipient_user_id_deleted_at_delivered_at_id", (q) =>
          q
            .eq("couple_id", recap.couple_id)
            .eq("recipient_user_id", counting.member_ids[member])
            .eq("deleted_at", undefined)
            .gte("delivered_at", startAt)
            .lt("delivered_at", endAt)),
    add: ({ counts }, letters) => {
      counts.letters += letters.filter((letter) => letter.state !== "sealed" && letter.moderation_status === "visible").length;
    },
  });
}

// Every source is an index range read. Rounds need three: the first partner's answers, the second's,
// then the couple's questions, since an answer does not say which couple it belongs to.
const SOURCES: Source<unknown>[] = [
  answersOf(0, ({ counting }, ids) => {
    counting.answered.push(...ids);
  }),
  answersOf(1, ({ counting }, ids) => {
    const first = new Set(counting.answered);
    counting.answered_by_both.push(...ids.filter((id) => first.has(id)));
  }),
  source<Doc<"daily_question_instances">>({
    rows: async ({ ctx, recap }) =>
      ctx.db
        .query("daily_question_instances")
        .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", recap.couple_id)),
    add: ({ counting, counts, recap }, instances) => {
      // Only the questions both answered matter from here on, and the row is written every call.
      counting.answered = [];
      const both = new Set(counting.answered_by_both);
      const rounds = instances.filter((instance) => both.has(instance.id) && instance.status !== "shuffled");
      counts.answered_together += rounds.length;
      counting.questions = rankBy(recap)([
        ...counting.questions,
        ...rounds.filter((round) => round.couple_day_id !== undefined).map((round) => round.id),
      ]);
    },
  }),
  source<Doc<"widget_drawing_revisions">>({
    rows: async ({ ctx, recap, startAt, endAt }) => {
      const canvas = await ctx.db
        .query("widget_canvases")
        .withIndex("by_couple_id", (q) => q.eq("couple_id", recap.couple_id))
        .unique();
      if (!canvas || canvas.deleted_at !== undefined) return null;
      return ctx.db
        .query("widget_drawing_revisions")
        .withIndex("by_canvas_id_created_at_id", (q) =>
          q.eq("canvas_id", canvas.id).gte("created_at", startAt).lt("created_at", endAt));
    },
    add: ({ counting, counts, recap }, revisions) => {
      const shown = revisions.filter((revision) => revision.deleted_at === undefined && revision.moderation_status === "visible");
      counts.drawings += shown.length;
      counting.drawings = rankBy(recap)([...counting.drawings, ...shown.map((revision) => revision.id)]);
    },
  }),
  source<Doc<"memories">>({
    rows: async ({ ctx, recap }) =>
      ctx.db
        .query("memories")
        .withIndex("by_couple_id_memory_date_id", (q) =>
          q.eq("couple_id", recap.couple_id).gte("memory_date", recap.period_start).lt("memory_date", recap.period_end)),
    add: ({ counting }, memories) => {
      // A memory's date can be edited between calls and move it past the cursor, so ids are kept once.
      const counted = new Set(counting.memories.map((memory) => memory.id));
      for (const memory of memories) {
        if (memory.deleted_at === undefined && memory.moderation_status === "visible" && !counted.has(memory.id)) {
          counting.memories.push({ id: memory.id, photos: 0 });
        }
      }
    },
  }),
  photosOf(0),
  photosOf(1),
  source<Doc<"stories">>({
    rows: async ({ ctx, recap, startAt, endAt }) =>
      ctx.db
        .query("stories")
        .withIndex("by_couple_id_created_at", (q) =>
          q.eq("couple_id", recap.couple_id).gte("created_at", startAt).lt("created_at", endAt)),
    add: ({ counts }, stories) => {
      counts.stories += stories.filter((story) => story.deleted_at === undefined).length;
    },
  }),
  lettersTo(0),
  lettersTo(1),
  source<Doc<"visits">>({
    rows: async ({ ctx, recap }) =>
      ctx.db
        .query("visits")
        .withIndex("by_couple_id_deleted_at_end_date", (q) =>
          q.eq("couple_id", recap.couple_id).eq("deleted_at", undefined).gte("end_date", recap.period_start)),
    add: ({ counting, recap }, visits) => {
      // A visit's end date can be edited between calls and move it past the cursor, so ids are kept once.
      const { period_start: start, period_end: end } = recap;
      const counted = new Set(counting.visits.map((visit) => visit.id));
      for (const visit of visits) {
        if (visit.start_date >= end || counted.has(visit.id)) continue;
        counting.visits.push({
          id: visit.id,
          first: visit.start_date > start ? visit.start_date : start,
          last: visit.end_date < end ? visit.end_date : addDaysToDate(end, -1),
        });
      }
    },
  }),
  source<Doc<"game_play_days">>({
    rows: async ({ ctx, recap }) =>
      ctx.db
        .query("game_play_days")
        .withIndex("by_couple_id_day", (q) =>
          q.eq("couple_id", recap.couple_id).gte("day", recap.period_start).lt("day", recap.period_end)),
    add: ({ counts, counting }, days) => {
      counts.game_days += days.filter((day) => counting.member_ids.every((userId) => day.user_ids.includes(userId))).length;
    },
  }),
];

/** The days inside at least one of the ranges, so days two visits share count once. */
function daysInAny(ranges: { first: string; last: string }[]): number {
  let days = 0;
  let reached: string | null = null;
  for (const { first, last } of [...ranges].sort((a, b) => a.first.localeCompare(b.first))) {
    const from = reached !== null && reached >= first ? addDaysToDate(reached, 1) : first;
    if (from <= last) days += daysBetweenDates(from, last) + 1;
    if (reached === null || last > reached) reached = last;
  }
  return days;
}

async function finish(ctx: WriterCtx, recap: Doc<"anniversary_recaps">, counting: Counting) {
  const hearts = await ctx.db
    .query("couple_hearts")
    .withIndex("by_couple_id_sender_user_id", (q) => q.eq("couple_id", recap.couple_id))
    .collect();
  const streak = await ctx.db
    .query("streak_states")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", recap.couple_id))
    .unique();
  const rank = rankBy(recap);
  const ids = (withPhotos: boolean) =>
    counting.memories.filter((memory) => memory.photos > 0 === withPhotos).map((memory) => memory.id);
  return {
    counts: {
      ...recap.counts,
      memories: counting.memories.length,
      memory_photos: counting.memories.reduce((total, memory) => total + memory.photos, 0),
      visits: counting.visits.length,
      visit_days: daysInAny(counting.visits),
      longest_streak_all_time: streak?.longest_count ?? 0,
    },
    hearts_sent: hearts.map((row) => ({ user_id: row.sender_user_id, count: row.sent_total })),
    counted_on: localDateOf(nowIso(), counting.time_zone),
    highlights: pickHighlights({
      photoMemories: rank(ids(true)),
      memories: rank(ids(false)),
      questions: counting.questions,
      drawings: counting.drawings,
    }),
    counting: undefined,
  };
}

/**
 * Counts as much of the recap as one call may read and saves where it stopped, or finishes it after
 * the last source. Returns the row as saved. Mutations are serializable, so two callers counting the
 * same row never count a page twice.
 */
export async function countRecapStep(
  ctx: WriterCtx,
  recapId: Id<"anniversary_recaps">,
): Promise<Doc<"anniversary_recaps"> | null> {
  const recap = await ctx.db.get(recapId);
  if (!recap?.counting) return recap;
  const counting = structuredClone(recap.counting);
  const step: Step = {
    ctx,
    recap,
    counting,
    counts: { ...recap.counts },
    startAt: startOfLocalDay(recap.period_start, counting.time_zone),
    endAt: startOfLocalDay(recap.period_end, counting.time_zone),
  };
  const next = () => {
    counting.source += 1;
    counting.cursor = null;
  };
  let read = 0;
  let paged = false;
  while (counting.source < SOURCES.length) {
    const { rows, add } = SOURCES[counting.source];
    if (counting.cursor === null) {
      if (read + PAGE + 1 > CALL_READS) break;
      const query = await rows(step);
      if (!query) {
        next();
        continue;
      }
      const all = await query.take(PAGE + 1);
      read += all.length;
      if (all.length <= PAGE) {
        add(step, all);
        next();
        continue;
      }
    }
    // Too big for one read: page through it, one page per call.
    if (paged || read + PAGE > CALL_READS) break;
    paged = true;
    const page = await (await rows(step))!.paginate({ numItems: PAGE, cursor: counting.cursor });
    read += page.page.length;
    add(step, page.page);
    if (page.isDone) {
      next();
    } else {
      counting.cursor = page.continueCursor;
      break;
    }
  }
  const done = counting.source >= SOURCES.length;
  await ctx.db.patch(recapId, done
    ? await finish(ctx, { ...recap, counts: step.counts }, counting)
    : { counts: step.counts, counting });
  return await ctx.db.get(recapId);
}
