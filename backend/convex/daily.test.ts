import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { currentQuestionFor, dailyQuestionsFor, insertAnswerAsset, seedCatalog, textQuestions } from "./daily.setup";
import { newUuid } from "./lib/ids";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, createSignedInUser, newTest, setTimeZone, type TestConvex, type TestUser } from "./test.setup";

const OSLO: [string, string] = ["Europe/Oslo", "Europe/Oslo"];
const CLIENT_ID = newUuid();
let sequence = 0;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T10:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

function op(at: string = new Date().toISOString()) {
  sequence += 1;
  return {
    p_client_operation_id: newUuid(),
    p_client_id: CLIENT_ID,
    p_client_sequence: sequence,
    p_local_created_at: at,
  };
}

const start = (user: TestUser, args = op()) =>
  user.as.mutation(api.daily.start_daily_challenge_snapshot, args).then(([snapshot]) => snapshot.questions);
const shuffle = (user: TestUser, args = op()) =>
  user.as.mutation(api.daily.shuffle_daily_question_snapshot, args).then(([snapshot]) => snapshot.questions);
const today = (user: TestUser) =>
  user.as.query(api.daily.get_today_daily_challenge_snapshot, {}).then(([snapshot]) => snapshot.questions);

function submit(user: TestUser, instanceId: string, payload: Record<string, unknown>, at?: string) {
  return user.as.mutation(api.daily.submit_daily_answer, { p_instance_id: instanceId, p_payload: payload, ...op(at) });
}

async function readyCouple(options: { timeZones?: [string, string]; questions?: Parameters<typeof seedCatalog>[1] } = {}) {
  const t = newTest();
  await seedCatalog(t, options.questions ?? textQuestions(12));
  const couple = await createCouple(t, { timeZones: options.timeZones ?? OSLO });
  await start(couple.first);
  const question = await currentQuestionFor(t, couple.first.userId);
  return { t, couple, a: couple.first, b: couple.second, question };
}

/** Moves the clock to 10:00 UTC on a day in October 2026 and starts that day. */
async function nextDay(user: TestUser, day: string) {
  vi.setSystemTime(new Date(`2026-10-${day}T10:00:00.000Z`));
  return await start(user);
}

describe("start_daily_challenge_snapshot", () => {
  test("stores the instance's couple and question for the chat's index", async () => {
    const { t, couple, question } = await readyCouple();
    const version = await t.run((ctx) =>
      ctx.db.query("question_versions").withIndex("by_uuid", (q) => q.eq("id", question.question_version_id)).unique(),
    );
    expect(question.couple_id).toBe(couple.coupleId);
    expect(question.question_id).toBe(version!.question_id);
  });

  test("seeds one question per couple day, and both partners get the same one", async () => {
    const { t, a, b, question } = await readyCouple();
    const aRows = await today(a);
    expect(aRows).toHaveLength(1);
    expect(aRows[0]).toMatchObject({
      instance_id: question.id,
      local_date: "2026-10-10",
      instance_status: "active",
      is_current_day: true,
      answer_kinds: ["text"],
      own_answer_id: null,
      partner_answer_id: null,
      can_view_partner_answer: false,
    });
    expect(aRows[0].prompt_en).toMatch(/prompt en$/);
    expect(aRows[0].prompt_nb).toMatch(/prompt nb$/);
    expect((await start(b)).map((row) => row.instance_id)).toEqual([question.id]);
    expect(await t.run((ctx) => ctx.db.query("daily_question_instances").collect())).toHaveLength(1);
  });

  test("a replay of the same client operation returns the same day and adds nothing", async () => {
    const { t, a } = await readyCouple();
    const args = op();
    const first = await start(a, args);
    const second = await start(a, args);
    expect(second.map((row) => row.instance_id)).toEqual(first.map((row) => row.instance_id));
    await start(a, op());
    expect(await t.run((ctx) => ctx.db.query("daily_question_instances").collect())).toHaveLength(1);
    await expect(
      start(a, { ...args, p_local_created_at: "2026-10-10T10:05:00.000Z" }),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
  });

  test("returns the snapshot shape the app decodes", async () => {
    const { a } = await readyCouple();
    const [snapshot] = await a.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(snapshot.questions).toHaveLength(1);
    expect(snapshot.answer_details).toEqual([]);
    expect(snapshot.streak).toEqual({
      current_count: 0,
      longest_count: 0,
      last_qualified_date: null,
      restore_available: false,
      restorable_count: 0,
      restore_deadline: null,
      freeze_available: false,
      freeze_ready_at: null,
      freeze_saved_streak: false,
      next_activity_deadline_at: null,
      current_user_contributed_today: false,
      partner_contributed_today: false,
    });
    expect(snapshot.generated_at).toBe("2026-10-10T10:00:00.000Z");
  });

  test("needs a signed-in user in an entitled couple", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(6));
    await expect(t.mutation(api.daily.start_daily_challenge_snapshot, op())).rejects.toThrow(/42501.*authenticated user required/);
    const lonely = await createSignedInUser(t);
    await expect(start(lonely)).rejects.toThrow(/42501.*active entitled couple access is required/);
    const unpaid = await createCouple(t, { entitled: false });
    await expect(start(unpaid.first)).rejects.toThrow(/42501.*active entitled couple access is required/);
  });

  test("fails with a clear error when no question is eligible", async () => {
    const t = newTest();
    await seedCatalog(t, []);
    const couple = await createCouple(t);
    await expect(start(couple.first)).rejects.toThrow(/22023.*no eligible daily questions are available/);
  });
});

describe("answers and the reveal rule", () => {
  test("a partner's answer stays hidden in every read until both have answered", async () => {
    const { t, a, b, question } = await readyCouple();
    const secret = "only for the reveal";
    const answerId = await submit(a, question.id, { text: secret });

    const bRows = await today(b);
    expect(bRows).toHaveLength(1);
    expect(bRows[0]).toMatchObject({ partner_answer_id: answerId, can_view_partner_answer: false, own_answer_id: null });

    const dayId = bRows[0].couple_day_id;
    const reads = [
      await b.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: dayId }),
      await b.as.query(api.daily.get_daily_answer_history_details, {}),
      await b.as.query(api.daily.get_daily_questions_history, {}),
      await b.as.query(api.daily.get_today_daily_challenge_snapshot, {}),
    ];
    expect(JSON.stringify(reads)).not.toContain(secret);
    expect(reads[0]).toEqual([expect.objectContaining({ answer_id: answerId, can_view_answer: false, text_body: null, media_asset_ids: [] })]);
    expect(reads[1]).toEqual([]);
    expect(reads[2]).toEqual([]);

    // The author sees their own text, the outsider sees nothing at all.
    const own = await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: dayId });
    expect(own[0]).toMatchObject({ can_view_answer: true, is_own_answer: true, text_body: secret });
    const outsider = await createCouple(t);
    expect(await outsider.first.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: dayId })).toEqual([]);

    // The partner answers, and now both sides see both answers.
    await submit(b, question.id, { text: "reply" });
    const afterB = await b.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: dayId });
    expect(afterB.map((item) => [item.text_body, item.can_view_answer]).sort()).toEqual([
      [secret, true],
      ["reply", true],
    ]);
    expect(await b.as.query(api.daily.get_daily_answer_history_details, {})).toHaveLength(2);
    expect((await today(a))[0].can_view_partner_answer).toBe(true);
    expect((await today(b))[0].can_view_partner_answer).toBe(true);
  });

  test("either partner can answer first, and someone outside the couple cannot answer at all", async () => {
    const { t, a, b, question } = await readyCouple();
    await expect(submit(b, question.id, { text: "me first" })).resolves.toEqual(expect.any(String));
    await expect(submit(a, question.id, { text: "then me" })).resolves.toEqual(expect.any(String));

    const outsider = await createCouple(t);
    await expect(submit(outsider.first, question.id, { text: "not mine" })).rejects.toThrow(
      /42501.*active entitled couple access is required/,
    );
    const lonely = await createSignedInUser(t);
    await expect(submit(lonely, question.id, { text: "not mine" })).rejects.toThrow(/42501/);
  });

  test("submitting twice with one client operation stores one answer", async () => {
    const { t, a, question } = await readyCouple();
    const args = { p_instance_id: question.id, p_payload: { text: "once", answer_id: newUuid().toUpperCase() }, ...op() };
    const answerId = await a.as.mutation(api.daily.submit_daily_answer, args);
    expect(await a.as.mutation(api.daily.submit_daily_answer, args)).toBe(answerId);
    expect(answerId).toBe(args.p_payload.answer_id.toLowerCase());
    expect(await t.run((ctx) => ctx.db.query("daily_question_answers").collect())).toHaveLength(1);
    expect(await t.run((ctx) => ctx.db.query("daily_answer_text").collect())).toHaveLength(1);
    await expect(
      a.as.mutation(api.daily.submit_daily_answer, { ...args, p_payload: { text: "changed", answer_id: args.p_payload.answer_id } }),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
    // A second operation for the same question hits the one-answer-per-person rule.
    await expect(submit(a, question.id, { text: "again" })).rejects.toThrow(
      /23505.*daily_question_answers_instance_user_unique/,
    );
  });

  test("validates the payload and the answer kinds", async () => {
    const { a, couple, question } = await readyCouple();
    const send = (payload: unknown) =>
      a.as.mutation(api.daily.submit_daily_answer, { p_instance_id: question.id, p_payload: payload, ...op() });
    await expect(send([])).rejects.toThrow(/23514.*answer payload must be an object/);
    await expect(send({})).rejects.toThrow(/23514.*answer payload must include at least one answer kind/);
    await expect(send({ text: "   " })).rejects.toThrow(/answer payload must include at least one answer kind/);
    await expect(send({ text: "x".repeat(2001) })).rejects.toThrow(/23514.*answer text is too long/);
    await expect(send({ text: "hi", extra: "x".repeat(20_000) })).rejects.toThrow(/23514.*answer payload is too large/);
    await expect(send({ partner_choice_user_id: couple.second.userId })).rejects.toThrow(
      /23514.*answer kind is not allowed for this question/,
    );
    await expect(send({ text: "hi", media_asset_ids: "nope" })).rejects.toThrow(/23514.*media_asset_ids must be an array/);
    await expect(send({ text: "hi", media_asset_ids: [newUuid()] })).rejects.toThrow(
      /23514.*daily answer media asset is not usable/,
    );
    await expect(send({ text: "hi", partner_choice_user_id: "not-a-uuid" })).rejects.toThrow(/22P02/);
    await expect(
      a.as.mutation(api.daily.submit_daily_answer, { p_instance_id: newUuid(), p_payload: { text: "x" }, ...op() }),
    ).rejects.toThrow(/22023.*daily question instance was not found/);
  });

  test("text plus photo answers attach media, and the photo stays hidden until the partner answers", async () => {
    const { t, couple, a, b, question } = await readyCouple({
      questions: textQuestions(12).map((item) => ({ ...item, kinds: ["text", "photo"] as ("text" | "photo")[] })),
    });
    const answerId = newUuid();
    const assetId = await insertAnswerAsset(t, { ownerUserId: a.userId, coupleId: couple.coupleId, answerId });
    await submit(a, question.id, { text: "caption", answer_id: answerId, media_asset_ids: [assetId.toUpperCase()] });
    const day = question.couple_day_id!;
    const mine = await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day });
    expect(mine[0]).toMatchObject({ text_body: "caption", media_asset_ids: [assetId], can_view_answer: true });
    const theirs = await b.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day });
    expect(theirs[0]).toMatchObject({ text_body: null, media_asset_ids: [], can_view_answer: false });
    // The asset has to be reserved for this answer, so tomorrow's question cannot reuse it.
    await nextDay(a, "11");
    const tomorrow = await currentQuestionFor(t, a.userId);
    await expect(submit(a, tomorrow.id, { text: "x", media_asset_ids: [assetId] })).rejects.toThrow(
      /23514.*daily answer media asset is not usable for this answer/,
    );
    // A hidden asset drops out of the list.
    await t.run(async (ctx) => {
      const asset = (await ctx.db.query("media_assets").collect())[0];
      await ctx.db.patch(asset._id, { moderation_status: "hidden" });
    });
    const hidden = await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day });
    expect(hidden[0].media_asset_ids).toEqual([]);
  });

  test("partner choice answers pick an active member and can be edited until the partner answers", async () => {
    const { t, couple, a, b, question } = await readyCouple({
      questions: textQuestions(12).map((item) => ({ ...item, kinds: ["text", "partner_choice"] as ("text" | "partner_choice")[] })),
    });
    const outsider = await createSignedInUser(t);
    await expect(submit(a, question.id, { partner_choice_user_id: outsider.userId })).rejects.toThrow(
      /23514.*partner choice must select an active couple member/,
    );
    const answerId = await submit(a, question.id, { partner_choice_user_id: a.userId.toUpperCase(), text: "me" });
    const day = question.couple_day_id!;
    expect((await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day }))[0].selected_user_id).toBe(a.userId);
    const edited = await a.as.mutation(api.daily.update_daily_answer_partner_choice, {
      p_instance_id: question.id,
      p_selected_user_id: couple.second.userId,
      ...op(),
    });
    expect(edited).toBe(answerId);
    expect((await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day }))[0].selected_user_id).toBe(
      couple.second.userId,
    );
    await expect(
      a.as.mutation(api.daily.update_daily_answer_partner_choice, { p_instance_id: question.id, p_selected_user_id: null, ...op() }),
    ).rejects.toThrow(/23514.*partner choice selection is required/);
    await submit(b, question.id, { text: "seen" });
    await expect(
      a.as.mutation(api.daily.update_daily_answer_partner_choice, {
        p_instance_id: question.id,
        p_selected_user_id: a.userId,
        ...op(),
      }),
    ).rejects.toThrow(/23514.*answers cannot be edited after your partner has answered/);
  });

  test("editing text moves the answered time and locks once the partner answers", async () => {
    const { a, b, question } = await readyCouple();
    const answerId = await submit(a, question.id, { text: "draft" });
    vi.setSystemTime(new Date("2026-10-10T10:30:00.000Z"));
    const edit = (user: TestUser, text: string | null) =>
      user.as.mutation(api.daily.update_daily_answer_text, { p_instance_id: question.id, p_text: text, ...op() });
    expect(await edit(a, "  better  ")).toBe(answerId);
    const [detail] = await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: question.couple_day_id! });
    expect(detail).toMatchObject({ text_body: "better", answered_at: "2026-10-10T10:30:00.000Z" });
    await expect(edit(a, "   ")).rejects.toThrow(/23514.*answer text is required/);
    await expect(edit(a, null)).rejects.toThrow(/23514.*answer text is required/);
    await expect(edit(a, "y".repeat(2001))).rejects.toThrow(/23514.*answer text is too long/);
    await expect(edit(b, "x")).rejects.toThrow(/22023.*there is no answer to edit/);
    await submit(b, question.id, { text: "my turn" });
    await expect(edit(a, "too late")).rejects.toThrow(/23514.*answers cannot be edited after your partner has answered/);
  });
});

describe("partner pushes", () => {
  const outboxFor = (t: TestConvex, user: TestUser) =>
    t.run(async (ctx) =>
      (await ctx.db.query("notification_outbox").collect()).filter((row) => row.recipient_user_id === user.userId),
    );
  const pushesDue = async (t: TestConvex, at = "2026-10-10T10:01:15.000Z") => {
    vi.setSystemTime(new Date(at));
    return await deliverDuePushes(t);
  };

  test("the first answer tells the partner, and the second tells the first that both answers are ready", async () => {
    const { t, a, b, question } = await readyCouple();
    await addDevice(t, a.userId);
    await addDevice(t, b.userId);
    await submit(a, question.id, { text: "hello" });
    expect((await outboxFor(t, b)).map((row) => row.kind)).toEqual(["daily_challenge_completed"]);
    // The push waits a little, so a quick answer from the partner can change it.
    expect(await deliverDuePushes(t)).toEqual([]);
    const [toB] = await pushesDue(t);
    expect(toB).toMatchObject({ title: "First Partner answered today's question" });
    expect(toB.payload).toMatchObject({
      type: "daily_challenge_completed",
      instance_ids: [question.id],
      deeplink: `paeonia://daily/today?coupleDayId=${question.couple_day_id}`,
    });

    vi.setSystemTime(new Date("2026-10-10T11:00:00.000Z"));
    await submit(b, question.id, { text: "hi" });
    expect((await outboxFor(t, a)).map((row) => row.kind)).toEqual(["partner_answered"]);
    const [toA] = await pushesDue(t, "2026-10-10T11:01:15.000Z");
    expect(toA).toMatchObject({ title: "Second Partner answered too" });
    expect(toA.payload).toMatchObject({
      type: "partner_answered",
      instance_ids: [question.id],
      question_count: 1,
      deeplink: `paeonia://daily/reveal?instanceId=${question.id}&coupleDayId=${question.couple_day_id}`,
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("answering back and seeing the reveal before the push goes out drops it", async () => {
    const { t, a, b, question } = await readyCouple();
    await addDevice(t, b.userId);
    await submit(a, question.id, { text: "hello" });
    await submit(b, question.id, { text: "quick reply" });
    await b.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: question.id });
    expect(await pushesDue(t)).toEqual([]);
    expect(await outboxFor(t, b)).toEqual([
      expect.objectContaining({ kind: "daily_challenge_completed", last_error: "notification is out of date" }),
    ]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("answering second without seeing the partner's answer still brings the push", async () => {
    // b composed before a's answer reached b's phone, so b's app showed no reveal.
    const { t, a, b, question } = await readyCouple();
    await addDevice(t, b.userId);
    await submit(a, question.id, { text: "hello" });
    await submit(b, question.id, { text: "sent before seeing it" });
    const [push] = await pushesDue(t);
    expect(push).toMatchObject({ title: "First Partner answered too" });
    expect(push.payload).toMatchObject({
      type: "partner_answered",
      deeplink: `paeonia://daily/reveal?instanceId=${question.id}&coupleDayId=${question.couple_day_id}`,
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an answer the first partner already opened sends nothing", async () => {
    const { t, a, b, question } = await readyCouple();
    await addDevice(t, a.userId);
    await submit(a, question.id, { text: "hello" });
    await submit(b, question.id, { text: "reply" });
    await a.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: question.id });
    expect(await pushesDue(t)).toEqual([]);
    expect(await outboxFor(t, a)).toEqual([
      expect.objectContaining({ kind: "partner_answered", last_error: "notification is out of date" }),
    ]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a late answer and today's answer in a row send one push for both", async () => {
    const { t, a, b, question: yesterday } = await readyCouple();
    await addDevice(t, b.userId);
    await submit(b, yesterday.id, { text: "waiting for you" });
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });

    await nextDay(a, "11");
    const todays = await currentQuestionFor(t, a.userId);
    await submit(a, yesterday.id, { text: "sorry, late" });
    await submit(a, todays.id, { text: "today" });
    expect(await outboxFor(t, b)).toHaveLength(1);
    const [push] = await pushesDue(t, "2026-10-11T10:01:15.000Z");
    // Today's question still waits for b, so the push asks for that answer.
    expect(push.payload).toMatchObject({
      type: "daily_challenge_completed",
      deeplink: `paeonia://daily/today?coupleDayId=${todays.couple_day_id}`,
    });
    expect([...(push.payload.instance_ids as string[])].sort()).toEqual([yesterday.id, todays.id].sort());
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("seen answers", () => {
  test("each side sees when the other first saw their answer", async () => {
    const { t, a, b, question } = await readyCouple();
    const seen = (user: TestUser) => user.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: question.id });
    const row = async (user: TestUser) => (await today(user)).find((item) => item.instance_id === question.id)!;

    await submit(a, question.id, { text: "mine" });
    // b can't read a's answer before answering, so b can't have seen it.
    await expect(seen(b)).rejects.toThrow(/23514.*partner answer is not visible yet/);

    vi.setSystemTime(new Date("2026-10-10T11:00:00.000Z"));
    await submit(b, question.id, { text: "reply" });
    expect(await row(a)).toMatchObject({ partner_answer_seen_at: null, own_answer_seen_by_partner_at: null });

    vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
    await seen(a);
    vi.setSystemTime(new Date("2026-10-10T13:00:00.000Z"));
    await seen(a);
    expect(await row(a)).toMatchObject({ partner_answer_seen_at: "2026-10-10T12:00:00.000Z", own_answer_seen_by_partner_at: null });
    expect(await row(b)).toMatchObject({ partner_answer_seen_at: null, own_answer_seen_by_partner_at: "2026-10-10T12:00:00.000Z" });
    const history = await b.as.query(api.daily.get_daily_questions_history, {});
    expect(history.find((item) => item.instance_id === question.id)).toMatchObject({
      own_answer_seen_by_partner_at: "2026-10-10T12:00:00.000Z",
    });

    const stranger = await createSignedInUser(t);
    await expect(
      stranger.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: question.id }),
    ).rejects.toThrow(/42501/);
  });
});

describe("shuffle", () => {
  test("swaps the day's question for both partners, skips the old one, and stops once someone answered", async () => {
    const { t, a, b, question: before } = await readyCouple();
    const rows = await shuffle(b);
    expect(rows).toHaveLength(1);
    const replaced = rows[0];
    expect(replaced.instance_id).not.toBe(before.id);
    expect(replaced.question_id).not.toBe(before.question_id);
    expect((await today(a)).map((row) => row.instance_id)).toEqual([replaced.instance_id]);
    const state = await t.run(async (ctx) => ({
      old: await ctx.db.query("daily_question_instances").withIndex("by_uuid", (q) => q.eq("id", before.id)).unique(),
      shuffles: await ctx.db.query("daily_question_shuffles").collect(),
    }));
    expect(state.old).toMatchObject({ status: "shuffled", replaced_by_instance_id: replaced.instance_id });
    expect(state.old?.replaced_at).toBe("2026-10-10T10:00:00.000Z");
    expect(state.shuffles).toEqual([
      expect.objectContaining({
        user_id: b.userId,
        skipped_instance_id: before.id,
        replacement_instance_id: replaced.instance_id,
        exclude_until: "2026-10-24T10:00:00.000Z",
      }),
    ]);

    await expect(submit(a, before.id, { text: "late" })).rejects.toThrow(/23514.*shuffled daily questions cannot be answered/);
    await expect(
      a.as.mutation(api.daily.update_daily_answer_text, { p_instance_id: before.id, p_text: "x", ...op() }),
    ).rejects.toThrow(/23514.*shuffled daily questions cannot be edited/);

    // Once the partner has answered, the question is theirs to share and stays.
    await submit(a, replaced.instance_id, { text: "answered" });
    await expect(shuffle(b)).rejects.toThrow(/23514.*answered daily questions cannot be shuffled/);
  });

  test("needs a signed-in user in an entitled couple", async () => {
    const { t } = await readyCouple();
    await expect(t.mutation(api.daily.shuffle_daily_question_snapshot, op())).rejects.toThrow(/42501.*authenticated user required/);
    const lonely = await createSignedInUser(t);
    await expect(shuffle(lonely)).rejects.toThrow(/42501.*active entitled couple access is required/);
    const unpaid = await createCouple(t, { entitled: false });
    await expect(shuffle(unpaid.first)).rejects.toThrow(/42501.*active entitled couple access is required/);
  });

  test("a replayed shuffle changes nothing the second time", async () => {
    const { t, a } = await readyCouple();
    const args = op();
    const first = await shuffle(a, args);
    const second = await shuffle(a, args);
    expect(second.map((row) => row.instance_id)).toEqual(first.map((row) => row.instance_id));
    expect(await t.run((ctx) => ctx.db.query("daily_question_shuffles").collect())).toHaveLength(1);
  });

  test("allows 30 shuffles a day per person and refuses the 31st", async () => {
    const { t, a } = await readyCouple({ questions: textQuestions(45) });
    for (let index = 0; index < 30; index += 1) {
      await shuffle(a);
    }
    await expect(shuffle(a)).rejects.toThrow(/23514.*daily shuffle limit reached/);
    expect(await t.run((ctx) => ctx.db.query("daily_question_shuffles").collect())).toHaveLength(30);
  }, 60_000);

  test("a skipped question stays out for both partners for 14 days", async () => {
    // Three questions: the day's question and two spares. Two skips use up the spares, and the
    // skipped ones and today's are all out, for either partner.
    const { a, b } = await readyCouple({ questions: textQuestions(3) });
    await shuffle(a);
    await shuffle(b);
    await expect(shuffle(a)).rejects.toThrow(/22023.*no eligible daily questions are available/);
    await expect(shuffle(b)).rejects.toThrow(/22023.*no eligible daily questions are available/);
  });
});

describe("time zones and day boundaries", () => {
  test("the couple day follows the westmost partner and bounds a first answer", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(12));
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/Los_Angeles"] });
    const at = "2026-10-10T23:30:00.000Z";
    vi.setSystemTime(new Date(at));
    const rows = await start(couple.first, op(at));
    expect(rows[0]).toMatchObject({ local_date: "2026-10-10", starts_at: "2026-10-10T07:00:00.000Z", ends_at: "2026-10-11T07:00:00.000Z" });
    const question = rows[0].instance_id;
    await expect(submit(couple.first, question, { text: "x" }, "2026-10-11T07:00:00.000Z")).rejects.toThrow(
      /23514.*daily answer timestamp is outside the question day/,
    );
    await expect(submit(couple.first, question, { text: "x" }, "2026-10-10T06:59:59.999Z")).rejects.toThrow(
      /23514.*daily answer timestamp is outside the question day/,
    );
    await expect(submit(couple.first, question, { text: "x" }, "2026-10-11T06:59:59.000Z")).resolves.toEqual(expect.any(String));
  });

  test("a start at the same instant lands on different couple days for different zones", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(12));
    const oslo = await createCouple(t, { timeZones: OSLO });
    const auckland = await createCouple(t, { timeZones: ["Pacific/Auckland", "Pacific/Auckland"] });
    const at = "2026-10-10T20:00:00.000Z";
    vi.setSystemTime(new Date(at));
    const [osloRow] = await start(oslo.first, op(at));
    const [aucklandRow] = await start(auckland.first, op(at));
    expect(osloRow.local_date).toBe("2026-10-10");
    expect(aucklandRow.local_date).toBe("2026-10-11");
  });

  test("a question one partner answered carries over, and the other can still answer it late", async () => {
    const { a, b, question } = await readyCouple();
    await submit(a, question.id, { text: "waiting" });
    await nextDay(b, "11");
    const rows = await today(b);
    expect(rows).toHaveLength(2);
    expect(rows[0].is_current_day).toBe(true);
    expect(rows[1]).toMatchObject({ instance_id: question.id, is_current_day: false, can_view_partner_answer: false, local_date: "2026-10-10" });
    // a sees it too, waiting for b.
    expect((await today(a)).map((row) => row.instance_id)).toContain(question.id);

    // b answers late and the exchange resolves. It stays on the list for the rest of the day it finished.
    await submit(b, question.id, { text: "sorry, late" });
    const after = (await today(b)).find((row) => row.instance_id === question.id)!;
    expect(after).toMatchObject({ is_current_day: false, can_view_partner_answer: true });
    await nextDay(b, "12");
    expect((await today(b)).some((row) => row.instance_id === question.id)).toBe(false);
  });

  test("a question nobody answered ends with its day", async () => {
    const { a, question } = await readyCouple();
    await nextDay(a, "11");
    expect((await today(a)).map((row) => row.instance_id)).not.toContain(question.id);
    await expect(submit(a, question.id, { text: "too late" })).rejects.toThrow(
      /23514.*daily answer timestamp is outside the question day/,
    );
  });
});

describe("history", () => {
  test("lists what the viewer answered, newest day first, with the day each exchange finished", async () => {
    const { t, a, b, question: first } = await readyCouple();
    await submit(a, first.id, { text: "one" });
    expect(await b.as.query(api.daily.get_daily_questions_history, {})).toEqual([]);
    vi.setSystemTime(new Date("2026-10-11T10:00:00.000Z"));
    await submit(b, first.id, { text: "reply" });
    await nextDay(a, "12");
    const third = await currentQuestionFor(t, a.userId);
    await submit(a, third.id, { text: "three" });
    const rows = await a.as.query(api.daily.get_daily_questions_history, {});
    expect(rows.map((row) => [row.instance_id, row.effective_local_date, row.can_view_partner_answer, row.is_current_day])).toEqual([
      [third.id, "2026-10-12", false, false],
      [first.id, "2026-10-11", true, false],
    ]);
    const details = await a.as.query(api.daily.get_daily_answer_history_details, {});
    expect(details.map((row) => row.text_body)).toEqual(["three", "one", "reply"]);
  });

  test("an exchange stays on the day it finished after a partner changes time zone", async () => {
    const { t, a, b, question } = await readyCouple();
    await submit(a, question.id, { text: "one" });
    // 07:00 on 2026-10-11 in Oslo, still 22:00 on 2026-10-10 in Los Angeles.
    vi.setSystemTime(new Date("2026-10-11T05:00:00.000Z"));
    await submit(b, question.id, { text: "reply" });
    const history = async () =>
      (await a.as.query(api.daily.get_daily_questions_history, {})).map((row) => row.effective_local_date);
    expect(await history()).toEqual(["2026-10-11"]);
    await setTimeZone(t, b.userId, "America/Los_Angeles");
    expect(await history()).toEqual(["2026-10-11"]);
  });
});

describe("questions the couple had before", () => {
  test("once every question was used, the one the couple had longest ago comes back first, even when it cannot resurface", async () => {
    const { t, a } = await readyCouple({ questions: textQuestions(3).map((item) => ({ ...item, resurfaceable: false })) });
    await nextDay(a, "11");
    await nextDay(a, "12");
    const [first, second, third] = await dailyQuestionsFor(t, a.userId);
    expect(new Set([first.question_id, second.question_id, third.question_id]).size).toBe(3);
    await nextDay(a, "13");
    expect((await currentQuestionFor(t, a.userId)).question_id).toBe(first.question_id);
  });

  test("a question that can resurface comes back after its window", async () => {
    const { t, a } = await readyCouple({
      questions: [{ key: "again", months: 1 }, { key: "once_a", resurfaceable: false }, { key: "once_b", resurfaceable: false }],
    });
    await nextDay(a, "11");
    await nextDay(a, "12");
    expect(await dailyQuestionsFor(t, a.userId)).toHaveLength(3);
    // A month later only "again" may come back, whatever order the three came in.
    vi.setSystemTime(new Date("2026-11-13T10:00:00.000Z"));
    await start(a);
    const [snapshot] = await a.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(snapshot.questions.find((row) => row.is_current_day)?.question_key).toBe("again");
  });
});

describe("get_daily_challenge_snapshot", () => {
  async function todayDayId(t: TestConvex) {
    return await t.run(async (ctx) => (await ctx.db.query("couple_days").first())!.id);
  }

  test("matches the start mutation's snapshot for the same day and names the day window", async () => {
    const { t, a } = await readyCouple();
    const dayId = await todayDayId(t);
    const [started] = await a.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    const [watched] = await a.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId });
    expect(watched).toEqual(started);
    expect(watched.questions).toHaveLength(1);
    expect(watched).toMatchObject({
      couple_day_id: dayId,
      local_date: "2026-10-10",
      starts_at: "2026-10-09T22:00:00.000Z",
      ends_at: "2026-10-10T22:00:00.000Z",
    });
    const [oneShot] = await a.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(oneShot.couple_day_id).toBe(dayId);
    expect(oneShot.ends_at).toBe(watched.ends_at);
  });

  test("today's snapshot ignores the day key and finds the new day after midnight", async () => {
    const { t, a } = await readyCouple();
    const dayId = await todayDayId(t);
    const [keyed] = await a.as.query(api.daily.get_today_daily_challenge_snapshot, { p_day_key: "2026-10-10" });
    expect(keyed.couple_day_id).toBe(dayId);
    vi.setSystemTime(new Date("2026-10-10T22:30:00.000Z"));
    const [afterMidnight] = await a.as.query(api.daily.get_today_daily_challenge_snapshot, {
      p_day_key: keyed.ends_at ?? undefined,
    });
    expect(afterMidnight.couple_day_id).toBeNull();
    expect(afterMidnight.ends_at).toBeNull();
  });

  test("accepts an uppercase id and does not change with the clock", async () => {
    const { t, a } = await readyCouple();
    const dayId = await todayDayId(t);
    const [first] = await a.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId.toUpperCase() });
    vi.setSystemTime(new Date("2026-10-10T15:00:00.000Z"));
    const [later] = await a.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId });
    expect(later).toEqual(first);
  });

  test("a shuffle, a partner's answer, and a reveal change the result", async () => {
    const { t, a, b } = await readyCouple();
    const dayId = await todayDayId(t);
    const read = async (user: TestUser) => (await user.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId }))[0];
    const before = await read(b);

    await shuffle(b);
    const shuffled = await read(b);
    expect(shuffled.questions.map((row) => row.instance_id)).not.toEqual(before.questions.map((row) => row.instance_id));
    const question = shuffled.questions[0].instance_id;

    await submit(a, question, { text: "hello" });
    const partnerAnswered = await read(b);
    expect(partnerAnswered.questions[0].partner_answer_id).not.toBeNull();
    expect(partnerAnswered.questions[0].can_view_partner_answer).toBe(false);
    expect(partnerAnswered.answer_details.every((row) => row.text_body === null || row.is_own_answer)).toBe(true);

    await submit(b, question, { text: "reply" });
    const revealed = await read(b);
    expect(revealed.questions[0].can_view_partner_answer).toBe(true);
    expect(revealed.answer_details.find((row) => !row.is_own_answer)!.text_body).toBe("hello");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the shuffle snapshot carries the day it shuffled", async () => {
    const { t, a } = await readyCouple();
    const dayId = await todayDayId(t);
    const [snapshot] = await a.as.mutation(api.daily.shuffle_daily_question_snapshot, op());
    expect(snapshot.couple_day_id).toBe(dayId);
  });

  test("fails for people outside the couple, unknown days, and signed-out callers", async () => {
    const { t, a } = await readyCouple();
    const dayId = await todayDayId(t);
    const outsider = await createCouple(t, { timeZones: OSLO });
    const denied = /42501.*active entitled couple access is required/;
    await expect(
      outsider.first.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId }),
    ).rejects.toThrow(denied);
    await expect(
      a.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: newUuid() }),
    ).rejects.toThrow(denied);
    await expect(t.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId })).rejects.toThrow(
      /42501.*authenticated user required/,
    );
    await expect(a.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: "nope" })).rejects.toThrow(/22P02/);
  });

  test("fails once the couple lost access", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(12));
    const couple = await createCouple(t, { timeZones: OSLO });
    await start(couple.first);
    const dayId = await todayDayId(t);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(row._id);
    });
    await expect(
      couple.first.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId }),
    ).rejects.toThrow(/42501/);
  });
});

describe("the streak", () => {
  test("each partner's answer counts, and both together start the streak", async () => {
    const { t, a, b, question } = await readyCouple();
    await submit(a, question.id, { text: "mine" });
    const events = await t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.map((row) => [row.activity_kind, row.user_id, row.couple_day_id])).toEqual([
      ["daily_answer_submitted", a.userId, question.couple_day_id],
    ]);
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual([
      expect.objectContaining({ current_count: 0, current_user_contributed_today: true, partner_contributed_today: false }),
    ]);
    const [partnerView] = await b.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: question.couple_day_id! });
    expect(partnerView.streak).toMatchObject({ current_user_contributed_today: false, partner_contributed_today: true });

    await submit(b, question.id, { text: "yours" });
    const [streak] = await b.as.query(api.streaks.get_couple_streak, {});
    expect(streak).toMatchObject({
      current_count: 1,
      longest_count: 1,
      last_qualified_date: "2026-10-10",
      // Local midnight two days after the qualifying day, in Oslo.
      next_activity_deadline_at: "2026-10-11T22:00:00.000Z",
      current_user_contributed_today: true,
      partner_contributed_today: true,
    });
    const [snapshot] = await b.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(snapshot.streak).toMatchObject({ current_count: 1 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a late answer counts on the day it was given", async () => {
    const { t, a, b, question } = await readyCouple();
    await submit(a, question.id, { text: "mine" });
    await nextDay(b, "11");
    const todays = await currentQuestionFor(t, b.userId);
    await submit(b, question.id, { text: "late" });
    const late = await t.run(async (ctx) =>
      (await ctx.db.query("couple_activity_events").collect()).find((row) => row.user_id === b.userId),
    );
    expect(late?.couple_day_id).toBe(todays.couple_day_id);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("reset_daily_challenge_for_testing", () => {
  test("clears today's answers and skips, then seeds a fresh question", async () => {
    const { t, couple, a, b, question: before } = await readyCouple();
    await shuffle(a);
    const question = await currentQuestionFor(t, a.userId);
    await submit(a, question.id, { text: "mine" });
    await submit(b, question.id, { text: "reply" });
    await a.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: question.id });
    const reset = await t.mutation(internal.daily.reset_daily_challenge_for_testing, { p_couple_id: couple.coupleId });
    expect(reset).toBe(1);
    const state = await t.run(async (ctx) => ({
      answers: await ctx.db.query("daily_question_answers").collect(),
      texts: await ctx.db.query("daily_answer_text").collect(),
      shuffles: await ctx.db.query("daily_question_shuffles").collect(),
      instances: await ctx.db.query("daily_question_instances").collect(),
      seen: await ctx.db.query("daily_answer_seen_states").collect(),
    }));
    expect(state.answers).toEqual([]);
    expect(state.seen).toEqual([]);
    expect(state.texts).toEqual([]);
    expect(state.shuffles).toEqual([]);
    expect(state.instances).toHaveLength(1);
    expect(state.instances[0].status).toBe("active");
    expect(state.instances.map((row) => row.id)).not.toContain(before.id);
    await expect(t.mutation(internal.daily.reset_daily_challenge_for_testing, { p_couple_id: null })).rejects.toThrow(
      /22023.*p_couple_id is required/,
    );
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
