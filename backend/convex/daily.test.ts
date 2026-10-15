import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { liveInstancesFor, insertAnswerAsset, seedCatalog, textQuestions } from "./daily.setup";
import { newUuid } from "./lib/ids";
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
const shuffle = (user: TestUser, slot: number, args = op()) =>
  user.as.mutation(api.daily.shuffle_daily_question_snapshot, { p_slot_number: slot, ...args }).then(([snapshot]) => snapshot.questions);
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
  return { t, couple, a: couple.first, b: couple.second };
}

async function completeDay(t: TestConvex, user: TestUser, text = "done") {
  const mine = (await liveInstancesFor(t, user.userId)).filter((row) => row.seeded_for_user_id === user.userId);
  for (const instance of mine.slice(-2)) {
    await submit(user, instance.id, { text });
  }
}

describe("start_daily_challenge_snapshot", () => {
  test("stores each instance's couple and question for the chat's index", async () => {
    const { t, couple, a } = await readyCouple();
    const instances = await liveInstancesFor(t, a.userId);
    expect(instances.length).toBeGreaterThan(0);
    for (const instance of instances) {
      const version = await t.run((ctx) =>
        ctx.db.query("question_versions").withIndex("by_uuid", (q) => q.eq("id", instance.question_version_id)).unique(),
      );
      expect(instance.couple_id).toBe(couple.coupleId);
      expect(instance.question_id).toBe(version!.question_id);
    }
  });

  test("seeds two slots per partner and shows each partner only their own questions", async () => {
    const { t, a, b } = await readyCouple();
    const aRows = await today(a);
    expect(aRows).toHaveLength(2);
    expect(aRows.every((row) => row.seeded_for_user_id === a.userId && row.is_current_day === true)).toBe(true);
    expect(aRows.map((row) => row.slot_number)).toEqual([1, 2]);
    expect(aRows[0]).toMatchObject({
      local_date: "2026-10-10",
      instance_status: "active",
      answer_kinds: ["text"],
      own_answer_id: null,
      partner_answer_id: null,
      can_view_partner_answer: false,
    });
    expect(aRows[0].prompt_en).toMatch(/prompt en$/);
    expect(aRows[0].prompt_nb).toMatch(/prompt nb$/);
    expect(await today(b)).toHaveLength(2);
    const challenges = await t.run((ctx) => ctx.db.query("daily_challenges").collect());
    expect(challenges).toHaveLength(2);
    const all = await t.run((ctx) => ctx.db.query("daily_question_instances").collect());
    expect(all).toHaveLength(4);
    // Two distinct questions per partner.
    for (const user of [a, b]) {
      const versions = all.filter((row) => row.seeded_for_user_id === user.userId).map((row) => row.question_version_id);
      expect(new Set(versions).size).toBe(2);
    }
  });

  test("a replay of the same client operation returns the same day and adds nothing", async () => {
    const { t, a } = await readyCouple();
    const args = op();
    const first = await start(a, args);
    const second = await start(a, args);
    expect(second.map((row) => row.instance_id)).toEqual(first.map((row) => row.instance_id));
    expect(await t.run((ctx) => ctx.db.query("daily_question_instances").collect())).toHaveLength(4);
    await start(a, op());
    expect(await t.run((ctx) => ctx.db.query("daily_question_instances").collect())).toHaveLength(4);
    await expect(
      start(a, { ...args, p_local_created_at: "2026-10-10T10:05:00.000Z" }),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
  });

  test("returns the snapshot shape the app decodes", async () => {
    const { a } = await readyCouple();
    const [snapshot] = await a.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(snapshot.questions).toHaveLength(2);
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
    const [started] = await a.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    expect(started.questions).toHaveLength(2);
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
    await seedCatalog(t, textQuestions(1));
    const couple = await createCouple(t);
    await expect(start(couple.first)).rejects.toThrow(/22023.*no eligible daily questions are available/);
  });
});

describe("answers and the reveal rule", () => {
  test("a partner's answer stays hidden in every read until both have answered", async () => {
    const { t, couple, a, b } = await readyCouple();
    const secret = "only for the reveal";
    const [aFirst] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const answerId = await submit(a, aFirst.id, { text: secret });

    const bRows = await today(b);
    const row = bRows.find((item) => item.instance_id === aFirst.id)!;
    expect(bRows).toHaveLength(3);
    expect(row).toMatchObject({ partner_answer_id: answerId, can_view_partner_answer: false, own_answer_id: null });

    const dayId = row.couple_day_id;
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
    await submit(b, aFirst.id, { text: "reply" });
    const afterB = await b.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: dayId });
    expect(afterB.map((item) => [item.text_body, item.can_view_answer]).sort()).toEqual([
      [secret, true],
      ["reply", true],
    ]);
    const history = await b.as.query(api.daily.get_daily_answer_history_details, {});
    expect(history).toHaveLength(2);
    const [bView] = (await b.as.query(api.daily.get_today_daily_challenge_snapshot, {}));
    expect(bView.questions.find((item) => item.instance_id === aFirst.id)?.can_view_partner_answer).toBe(true);
    expect(couple.coupleId).toBeTruthy();
  });

  test("a partner-seeded question can only be answered after the partner answers", async () => {
    const { t, a, b } = await readyCouple();
    const [aFirst] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await expect(submit(b, aFirst.id, { text: "too early" })).rejects.toThrow(
      /42501.*partner-seeded questions can be answered after your partner answers/,
    );
    await submit(a, aFirst.id, { text: "first" });
    await expect(submit(b, aFirst.id, { text: "ok now" })).resolves.toEqual(expect.any(String));
  });

  test("submitting twice with one client operation stores one answer", async () => {
    const { t, a } = await readyCouple();
    const [first] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const args = { p_instance_id: first.id, p_payload: { text: "once", answer_id: newUuid().toUpperCase() }, ...op() };
    const answerId = await a.as.mutation(api.daily.submit_daily_answer, args);
    expect(await a.as.mutation(api.daily.submit_daily_answer, args)).toBe(answerId);
    expect(answerId).toBe(args.p_payload.answer_id.toLowerCase());
    expect(await t.run((ctx) => ctx.db.query("daily_question_answers").collect())).toHaveLength(1);
    expect(await t.run((ctx) => ctx.db.query("daily_answer_text").collect())).toHaveLength(1);
    await expect(
      a.as.mutation(api.daily.submit_daily_answer, { ...args, p_payload: { text: "changed", answer_id: args.p_payload.answer_id } }),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
    // A second operation for the same question hits the one-answer-per-person rule.
    await expect(submit(a, first.id, { text: "again" })).rejects.toThrow(
      /23505.*daily_question_answers_instance_user_unique/,
    );
  });

  test("validates the payload and the answer kinds", async () => {
    const { t, a, couple } = await readyCouple({
      questions: [
        { key: "text_only" },
        ...textQuestions(11).map((item) => ({ ...item, key: `x_${item.key}` })),
      ],
    });
    const [first] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const send = (payload: unknown) =>
      a.as.mutation(api.daily.submit_daily_answer, { p_instance_id: first.id, p_payload: payload, ...op() });
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
    const { t, couple, a, b } = await readyCouple({
      questions: textQuestions(12).map((item) => ({ ...item, kinds: ["text", "photo"] as ("text" | "photo")[] })),
    });
    const [first] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const answerId = newUuid();
    const assetId = await insertAnswerAsset(t, { ownerUserId: a.userId, coupleId: couple.coupleId, answerId });
    await submit(a, first.id, { text: "caption", answer_id: answerId, media_asset_ids: [assetId.toUpperCase()] });
    const day = (await today(a))[0].couple_day_id;
    const mine = await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day });
    expect(mine[0]).toMatchObject({ text_body: "caption", media_asset_ids: [assetId], can_view_answer: true });
    const theirs = await b.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day });
    expect(theirs[0]).toMatchObject({ text_body: null, media_asset_ids: [], can_view_answer: false });
    // The asset has to be reserved for this answer.
    const [second] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId).slice(1);
    await expect(submit(a, second.id, { text: "x", media_asset_ids: [assetId] })).rejects.toThrow(
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
    const { t, couple, a, b } = await readyCouple({
      questions: textQuestions(12).map((item) => ({ ...item, kinds: ["text", "partner_choice"] as ("text" | "partner_choice")[] })),
    });
    const [first] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const outsider = await createSignedInUser(t);
    await expect(submit(a, first.id, { partner_choice_user_id: outsider.userId })).rejects.toThrow(
      /23514.*partner choice must select an active couple member/,
    );
    const answerId = await submit(a, first.id, { partner_choice_user_id: a.userId.toUpperCase(), text: "me" });
    const day = (await today(a))[0].couple_day_id;
    expect((await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day }))[0].selected_user_id).toBe(a.userId);
    const edited = await a.as.mutation(api.daily.update_daily_answer_partner_choice, {
      p_instance_id: first.id,
      p_selected_user_id: couple.second.userId,
      ...op(),
    });
    expect(edited).toBe(answerId);
    expect((await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day }))[0].selected_user_id).toBe(
      couple.second.userId,
    );
    await expect(
      a.as.mutation(api.daily.update_daily_answer_partner_choice, { p_instance_id: first.id, p_selected_user_id: null, ...op() }),
    ).rejects.toThrow(/23514.*partner choice selection is required/);
    await submit(b, first.id, { text: "seen" });
    await expect(
      a.as.mutation(api.daily.update_daily_answer_partner_choice, {
        p_instance_id: first.id,
        p_selected_user_id: a.userId,
        ...op(),
      }),
    ).rejects.toThrow(/23514.*answers cannot be edited after your partner has answered/);
  });

  test("editing text moves the answered time and locks once the partner answers", async () => {
    const { t, a, b } = await readyCouple();
    const [first] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const answerId = await submit(a, first.id, { text: "draft" });
    vi.setSystemTime(new Date("2026-10-10T10:30:00.000Z"));
    const edit = (text: string | null) =>
      a.as.mutation(api.daily.update_daily_answer_text, { p_instance_id: first.id, p_text: text, ...op() });
    expect(await edit("  better  ")).toBe(answerId);
    const day = (await today(a))[0].couple_day_id;
    const [detail] = await a.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: day });
    expect(detail).toMatchObject({ text_body: "better", answered_at: "2026-10-10T10:30:00.000Z" });
    await expect(edit("   ")).rejects.toThrow(/23514.*answer text is required/);
    await expect(edit(null)).rejects.toThrow(/23514.*answer text is required/);
    await expect(edit("y".repeat(2001))).rejects.toThrow(/23514.*answer text is too long/);
    const [second] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId).slice(1);
    await expect(
      a.as.mutation(api.daily.update_daily_answer_text, { p_instance_id: second.id, p_text: "x", ...op() }),
    ).rejects.toThrow(/22023.*there is no answer to edit/);
    await submit(b, first.id, { text: "my turn" });
    await expect(edit("too late")).rejects.toThrow(/23514.*answers cannot be edited after your partner has answered/);
  });

  test("tells the first partner when the second answers", async () => {
    const { t, a, b } = await readyCouple();
    await addDevice(t, a.userId);
    const [first] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(a, first.id, { text: "hello" });
    expect(await t.run((ctx) => ctx.db.query("notification_outbox").collect())).toHaveLength(0);
    await submit(b, first.id, { text: "hi" });
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.map((row) => [row.kind, row.recipient_user_id])).toEqual([["partner_answered", a.userId]]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("seen answers", () => {
  test("each side sees when the other first saw their answer", async () => {
    const { t, a, b } = await readyCouple();
    const [aFirst] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const seen = (user: TestUser) => user.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: aFirst.id });
    const row = async (user: TestUser) => (await today(user)).find((item) => item.instance_id === aFirst.id)!;

    await submit(a, aFirst.id, { text: "mine" });
    // b can't read a's answer before answering, so b can't have seen it.
    await expect(seen(b)).rejects.toThrow(/23514.*partner answer is not visible yet/);

    vi.setSystemTime(new Date("2026-10-10T11:00:00.000Z"));
    await submit(b, aFirst.id, { text: "reply" });
    expect(await row(a)).toMatchObject({ partner_answer_seen_at: null, own_answer_seen_by_partner_at: null });

    vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
    await seen(a);
    vi.setSystemTime(new Date("2026-10-10T13:00:00.000Z"));
    await seen(a);
    expect(await row(a)).toMatchObject({ partner_answer_seen_at: "2026-10-10T12:00:00.000Z", own_answer_seen_by_partner_at: null });
    expect(await row(b)).toMatchObject({ partner_answer_seen_at: null, own_answer_seen_by_partner_at: "2026-10-10T12:00:00.000Z" });
    const history = await b.as.query(api.daily.get_daily_questions_history, {});
    expect(history.find((item) => item.instance_id === aFirst.id)).toMatchObject({
      own_answer_seen_by_partner_at: "2026-10-10T12:00:00.000Z",
    });

    const stranger = await createSignedInUser(t);
    await expect(
      stranger.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: aFirst.id }),
    ).rejects.toThrow(/42501/);
  });
});

describe("shuffle", () => {
  test("replaces a slot, skips the old question, and refuses answered or shuffled slots", async () => {
    const { t, a } = await readyCouple({ questions: textQuestions(12) });
    const before = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const oldVersions = new Set(before.map((row) => row.question_version_id));
    const rows = await shuffle(a, 2);
    expect(rows).toHaveLength(2);
    const replaced = rows.find((row) => row.slot_number === 2)!;
    expect(replaced.instance_id).not.toBe(before[1].id);
    expect(oldVersions.has(replaced.question_version_id)).toBe(false);
    const state = await t.run(async (ctx) => ({
      old: await ctx.db.query("daily_question_instances").withIndex("by_uuid", (q) => q.eq("id", before[1].id)).unique(),
      shuffles: await ctx.db.query("daily_question_shuffles").collect(),
    }));
    expect(state.old).toMatchObject({ status: "shuffled", replaced_by_instance_id: replaced.instance_id });
    expect(state.old?.replaced_at).toBe("2026-10-10T10:00:00.000Z");
    expect(state.shuffles).toHaveLength(1);
    expect(state.shuffles[0]).toMatchObject({
      slot_number: 2,
      skipped_instance_id: before[1].id,
      replacement_instance_id: replaced.instance_id,
      exclude_until: "2026-10-24T10:00:00.000Z",
    });

    await expect(submit(a, before[1].id, { text: "late" })).rejects.toThrow(
      /23514.*shuffled daily questions cannot be answered/,
    );
    await expect(
      a.as.mutation(api.daily.update_daily_answer_text, { p_instance_id: before[1].id, p_text: "x", ...op() }),
    ).rejects.toThrow(/23514.*shuffled daily questions cannot be edited/);

    await submit(a, before[0].id, { text: "answered" });
    // Answering moves the slot to 'answered', so it no longer counts as an active slot.
    await expect(shuffle(a, 1)).rejects.toThrow(
      /22023.*active daily question slot was not found/,
    );
    await expect(shuffle(a, 3)).rejects.toThrow(
      /23514.*slot number is out of range/,
    );
    const [snapshot] = await a.as.mutation(api.daily.shuffle_daily_question_snapshot, { p_slot_number: 2, ...op() });
    expect(snapshot.questions).toHaveLength(2);
  });

  test("a replayed shuffle changes nothing the second time", async () => {
    const { t, a } = await readyCouple();
    const args = op();
    const first = await shuffle(a, 1, args);
    const second = await shuffle(a, 1, args);
    expect(second.map((row) => row.instance_id)).toEqual(first.map((row) => row.instance_id));
    expect(await t.run((ctx) => ctx.db.query("daily_question_shuffles").collect())).toHaveLength(1);
  });

  test("allows 30 shuffles a day and refuses the 31st", async () => {
    const { t, a } = await readyCouple({ questions: textQuestions(45) });
    for (let index = 0; index < 30; index += 1) {
      await shuffle(a, (index % 2) + 1);
    }
    await expect(shuffle(a, 1)).rejects.toThrow(
      /23514.*daily shuffle limit reached/,
    );
    expect(await t.run((ctx) => ctx.db.query("daily_question_shuffles").collect())).toHaveLength(30);
  }, 60_000);

  test("skipped questions do not come back for 14 days", async () => {
    const { t, a } = await readyCouple({ questions: textQuestions(4) });
    const original = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    // Four questions: two live plus two spare. Two shuffles use up the spares and a third has nothing left.
    await shuffle(a, 1);
    await shuffle(a, 1);
    await expect(shuffle(a, 1)).rejects.toThrow(
      /22023.*no eligible daily questions are available/,
    );
    expect(original).toHaveLength(2);
  });
});

describe("time zones and day boundaries", () => {
  test("the couple day follows the westmost partner and bounds the seeded user's answers", async () => {
    const t = newTest();
    await seedCatalog(t, textQuestions(12));
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/Los_Angeles"] });
    const at = "2026-10-10T23:30:00.000Z";
    vi.setSystemTime(new Date(at));
    const rows = await start(couple.first, op(at));
    expect(rows[0]).toMatchObject({ local_date: "2026-10-10", starts_at: "2026-10-10T07:00:00.000Z", ends_at: "2026-10-11T07:00:00.000Z" });
    const [mine] = (await liveInstancesFor(t, couple.first.userId)).filter((row) => row.seeded_for_user_id === couple.first.userId);
    await expect(submit(couple.first, mine.id, { text: "x" }, "2026-10-11T07:00:00.000Z")).rejects.toThrow(
      /23514.*daily answer timestamp is outside the question day/,
    );
    await expect(submit(couple.first, mine.id, { text: "x" }, "2026-10-10T06:59:59.999Z")).rejects.toThrow(
      /23514.*daily answer timestamp is outside the question day/,
    );
    await expect(submit(couple.first, mine.id, { text: "x" }, "2026-10-11T06:59:59.000Z")).resolves.toEqual(expect.any(String));
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

  test("an unfinished exchange from yesterday carries over to today", async () => {
    const { t, a, b } = await readyCouple();
    const [aFirst] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(a, aFirst.id, { text: "waiting" });
    vi.setSystemTime(new Date("2026-10-11T10:00:00.000Z"));
    await start(b);
    const rows = await today(b);
    const carried = rows.find((row) => row.instance_id === aFirst.id)!;
    expect(carried).toMatchObject({ is_current_day: false, can_view_partner_answer: false, local_date: "2026-10-10" });
    expect(rows.filter((row) => row.is_current_day === true)).toHaveLength(2);
    expect(rows[0].is_current_day).toBe(true);
    expect(rows[rows.length - 1].instance_id).toBe(aFirst.id);
    // B answers late and the exchange resolves; it stays on the list for the rest of the day it finished.
    await submit(b, aFirst.id, { text: "sorry, late" });
    const after = (await today(b)).find((row) => row.instance_id === aFirst.id)!;
    expect(after).toMatchObject({ is_current_day: false, can_view_partner_answer: true });
    vi.setSystemTime(new Date("2026-10-12T10:00:00.000Z"));
    await start(b);
    expect((await today(b)).some((row) => row.instance_id === aFirst.id)).toBe(false);
  });
});

describe("history", () => {
  test("lists what the viewer answered, newest day first, with the day each exchange finished", async () => {
    const { t, a, b } = await readyCouple();
    const [aFirst, aSecond] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(a, aFirst.id, { text: "one" });
    expect(await b.as.query(api.daily.get_daily_questions_history, {})).toEqual([]);
    vi.setSystemTime(new Date("2026-10-11T10:00:00.000Z"));
    await submit(b, aFirst.id, { text: "reply" });
    vi.setSystemTime(new Date("2026-10-12T10:00:00.000Z"));
    await submit(a, aSecond.id, { text: "two" }, "2026-10-10T20:00:00.000Z");
    const rows = await a.as.query(api.daily.get_daily_questions_history, {});
    expect(rows.map((row) => [row.instance_id, row.effective_local_date, row.can_view_partner_answer, row.is_current_day])).toEqual([
      [aSecond.id, "2026-10-12", false, false],
      [aFirst.id, "2026-10-11", true, false],
    ]);
    const details = await a.as.query(api.daily.get_daily_answer_history_details, {});
    expect(details.map((row) => row.text_body)).toEqual(["one", "reply", "two"]);
  });

  test("an exchange stays on the day it finished after a partner changes time zone", async () => {
    const { t, a, b } = await readyCouple();
    const [aFirst] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(a, aFirst.id, { text: "one" });
    // 07:00 on 2026-10-11 in Oslo, still 22:00 on 2026-10-10 in Los Angeles.
    vi.setSystemTime(new Date("2026-10-11T05:00:00.000Z"));
    await submit(b, aFirst.id, { text: "reply" });
    const history = async () =>
      (await a.as.query(api.daily.get_daily_questions_history, {})).map((row) => row.effective_local_date);
    expect(await history()).toEqual(["2026-10-11"]);
    await setTimeZone(t, b.userId, "America/Los_Angeles");
    expect(await history()).toEqual(["2026-10-11"]);
  });

});

describe("questions already answered", () => {
  test("once everything is answered, the question answered longest ago comes back first, even when it cannot resurface", async () => {
    // Three questions that never resurface. Day one answers two of them, the first at 10:00 and the second at 12:00.
    const { t, a } = await readyCouple({ questions: textQuestions(3).map((item) => ({ ...item, resurfaceable: false })) });
    const first = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(a, first[0].id, { text: "early" });
    vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
    await submit(a, first[1].id, { text: "late" });
    // Tomorrow: the one unanswered question fills slot 1, and slot 2 has nothing left but answered questions.
    vi.setSystemTime(new Date("2026-10-11T10:00:00.000Z"));
    await start(a);
    const versions = (await today(a)).filter((row) => row.is_current_day === true).map((row) => row.question_version_id);
    expect(versions).toHaveLength(2);
    expect(versions).toContain(first[0].question_version_id);
    expect(versions).not.toContain(first[1].question_version_id);
  });

  test("a shuffle never brings back a question the user already answered today", async () => {
    // Two questions: slot 1 is answered, so shuffling slot 2 has no other question to give.
    const { t, a } = await readyCouple({ questions: textQuestions(2) });
    const own = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    const slotOne = own.find((row) => row.slot_number === 1)!;
    await submit(a, slotOne.id, { text: "answered" });
    await expect(shuffle(a, 2)).rejects.toThrow(/22023.*no eligible daily questions are available/);
    const sameQuestionToday = (await t.run((ctx) => ctx.db.query("daily_question_instances").collect())).filter(
      (row) => row.seeded_for_user_id === a.userId && row.question_version_id === slotOne.question_version_id,
    );
    expect(sameQuestionToday).toHaveLength(1);
  });

  test("a question that can resurface comes back after its window", async () => {
    const { t, a } = await readyCouple({ questions: textQuestions(3).map((item) => ({ ...item, months: 1 })) });
    await completeDay(t, a);
    vi.setSystemTime(new Date("2026-11-11T10:00:00.000Z"));
    const rows = await start(a);
    expect(rows.filter((row) => row.is_current_day === true)).toHaveLength(2);
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
    expect(watched.questions).toHaveLength(2);
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

  test("a partner's answer, a reveal, and a shuffle change the result", async () => {
    const { t, a, b } = await readyCouple();
    const dayId = await todayDayId(t);
    const read = async (user: TestUser) => (await user.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId }))[0];
    const before = await read(b);
    const [aFirst] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);

    await submit(a, aFirst.id, { text: "hello" });
    const partnerAnswered = await read(b);
    expect(partnerAnswered).not.toEqual(before);
    const aRow = partnerAnswered.questions.find((row) => row.instance_id === aFirst.id)!;
    expect(aRow.partner_answer_id).not.toBeNull();
    expect(aRow.can_view_partner_answer).toBe(false);
    expect(partnerAnswered.answer_details.every((row) => row.text_body === null || row.is_own_answer)).toBe(true);

    await submit(b, aFirst.id, { text: "reply" });
    const revealed = await read(b);
    expect(revealed.questions.find((row) => row.instance_id === aFirst.id)!.can_view_partner_answer).toBe(true);
    expect(revealed.answer_details.find((row) => !row.is_own_answer)!.text_body).toBe("hello");

    const mineB = (await liveInstancesFor(t, b.userId)).filter((row) => row.seeded_for_user_id === b.userId);
    await b.as.mutation(api.daily.shuffle_daily_question_snapshot, { p_slot_number: mineB[1].slot_number, ...op() });
    const shuffled = await read(b);
    expect(shuffled.questions.map((row) => row.instance_id)).not.toEqual(revealed.questions.map((row) => row.instance_id));
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the shuffle snapshot carries the day it shuffled", async () => {
    const { t, a } = await readyCouple();
    const dayId = await todayDayId(t);
    const [snapshot] = await a.as.mutation(api.daily.shuffle_daily_question_snapshot, { p_slot_number: 1, ...op() });
    expect(snapshot.couple_day_id).toBe(dayId);
  });

  test("shows the streak with the day's contributions", async () => {
    const { t, a, b } = await readyCouple();
    const dayId = await todayDayId(t);
    await completeDay(t, a);
    const [snapshot] = await b.as.query(api.daily.get_daily_challenge_snapshot, { p_couple_day_id: dayId });
    expect(snapshot.streak).toMatchObject({ current_user_contributed_today: false, partner_contributed_today: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
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

describe("completing the day", () => {
  test("two answers complete the challenge, tell the partner, and both partners together start the streak", async () => {
    const { t, a, b } = await readyCouple();
    await addDevice(t, b.userId);
    await completeDay(t, a);
    const challenge = await t.run(async (ctx) =>
      (await ctx.db.query("daily_challenges").collect()).find((row) => row.user_id === a.userId),
    );
    expect(challenge).toMatchObject({ completed_at: "2026-10-10T10:00:00.000Z", partner_notified_at: "2026-10-10T10:00:00.000Z" });
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.map((row) => [row.kind, row.recipient_user_id])).toEqual([["daily_challenge_completed", b.userId]]);
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual([
      expect.objectContaining({ current_count: 0, current_user_contributed_today: true, partner_contributed_today: false }),
    ]);
    expect(await t.run((ctx) => ctx.db.query("streak_states").collect())).toEqual([]);

    await completeDay(t, b);
    const [streak] = await b.as.query(api.streaks.get_couple_streak, {});
    expect(streak).toEqual({
      current_count: 1,
      longest_count: 1,
      last_qualified_date: "2026-10-10",
      restore_available: false,
      restorable_count: 0,
      restore_deadline: null,
      freeze_available: false,
      freeze_ready_at: null,
      freeze_saved_streak: false,
      // Local midnight two days after the qualifying day, in Oslo.
      next_activity_deadline_at: "2026-10-11T22:00:00.000Z",
      current_user_contributed_today: true,
      partner_contributed_today: true,
    });
    const [snapshot] = await b.as.query(api.daily.get_today_daily_challenge_snapshot, {});
    expect(snapshot.streak).toMatchObject({ current_count: 1 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("one answered slot is not enough", async () => {
    const { t, a } = await readyCouple();
    const mine = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(a, mine[0].id, { text: "1" });
    const challenge = await t.run(async (ctx) =>
      (await ctx.db.query("daily_challenges").collect()).find((row) => row.user_id === a.userId),
    );
    expect(challenge?.completed_at).toBeUndefined();
    expect(await t.run((ctx) => ctx.db.query("couple_activity_events").collect())).toEqual([]);
  });
});

describe("reset_daily_challenge_for_testing", () => {
  test("clears today's answers, skips, and completion, then seeds fresh slots", async () => {
    const { t, couple, a, b } = await readyCouple();
    const before = await liveInstancesFor(t, a.userId);
    await shuffle(a, 1);
    await completeDay(t, a);
    const [answered] = (await liveInstancesFor(t, a.userId)).filter((row) => row.seeded_for_user_id === a.userId);
    await submit(b, answered.id, { text: "reply" });
    await a.as.mutation(api.chatPresence.mark_daily_answer_seen, { p_instance_id: answered.id });
    const reset = await t.mutation(internal.daily.reset_daily_challenge_for_testing, { p_couple_id: couple.coupleId });
    expect(reset).toBe(1);
    const state = await t.run(async (ctx) => ({
      answers: await ctx.db.query("daily_question_answers").collect(),
      texts: await ctx.db.query("daily_answer_text").collect(),
      shuffles: await ctx.db.query("daily_question_shuffles").collect(),
      instances: await ctx.db.query("daily_question_instances").collect(),
      challenges: await ctx.db.query("daily_challenges").collect(),
      seen: await ctx.db.query("daily_answer_seen_states").collect(),
    }));
    expect(state.answers).toEqual([]);
    expect(state.seen).toEqual([]);
    expect(state.texts).toEqual([]);
    expect(state.shuffles).toEqual([]);
    expect(state.instances).toHaveLength(4);
    expect(state.instances.every((row) => row.status === "active")).toBe(true);
    expect(state.instances.map((row) => row.id)).not.toContain(before[0].id);
    expect(state.challenges.every((row) => row.completed_at === undefined && row.partner_notified_at === undefined)).toBe(true);
    await expect(t.mutation(internal.daily.reset_daily_challenge_for_testing, { p_couple_id: null })).rejects.toThrow(
      /22023.*p_couple_id is required/,
    );
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
