import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { answeredRound, answerIdOf, seedQuestion } from "./dailyChat.setup";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const MARCH = "2026-03-03T12:00:00.000Z";
const OCTOBER = "2026-10-09T12:00:00.000Z";

describe("get_daily_question_chat", () => {
  test("lists every round of the question, oldest first, and leaves other questions out", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const other = await seedQuestion(t);
    const later = await answeredRound(t, couple, question, { at: OCTOBER });
    const earlier = await answeredRound(t, couple, question, { at: MARCH });
    await answeredRound(t, couple, other, { at: MARCH });

    const chat = await couple.first.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: question.id });
    expect(chat.questions.map((row) => row.instance_id)).toEqual([earlier, later]);
    expect(chat.questions.map((row) => row.local_date)).toEqual(["2026-03-03", "2026-10-09"]);
    expect(chat.questions.every((row) => row.question_id === question.id && row.chat_available === true)).toBe(true);
    expect(chat.thread_id).toBeNull();
  });

  test("applies the reveal rule to each round on its own", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const texts = {
      [couple.first.userId]: "first says",
      [couple.second.userId]: "second says",
    };
    // March: only the partner answered, so the viewer never earned that answer.
    const march = await answeredRound(t, couple, question, { at: MARCH, answeredBy: [couple.second], texts });
    // October: both answered.
    const october = await answeredRound(t, couple, question, { at: OCTOBER, texts });

    const chat = await couple.first.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: question.id });
    const detail = (instanceId: string, userId: string) =>
      chat.answer_details.find((row) => row.instance_id === instanceId && row.answer_user_id === userId)!;
    expect(detail(march, couple.second.userId)).toMatchObject({ can_view_answer: false, text_body: null, is_own_answer: false });
    expect(detail(october, couple.second.userId)).toMatchObject({ can_view_answer: true, text_body: "second says" });
    expect(detail(october, couple.first.userId)).toMatchObject({ can_view_answer: true, text_body: "first says", is_own_answer: true });
    const marchRow = chat.questions.find((row) => row.instance_id === march)!;
    expect(marchRow).toMatchObject({ own_answer_id: null, can_view_partner_answer: false });
    const octoberRow = chat.questions.find((row) => row.instance_id === october)!;
    expect(octoberRow.can_view_partner_answer).toBe(true);

    // The partner answered March, so they always read their own answer there.
    const partnerChat = await couple.second.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: question.id });
    expect(partnerChat.answer_details.find((row) => row.instance_id === march)).toMatchObject({
      can_view_answer: true,
      text_body: "second says",
    });
  });

  test("returns the chat's thread once it has been started", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    await answeredRound(t, couple, question, { at: MARCH });
    await answeredRound(t, couple, question, { at: OCTOBER, answeredBy: [couple.first] });
    const [message] = await couple.first.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_couple_id: couple.coupleId,
      p_question_id: question.id,
      p_body: "remember this?",
    });
    const chat = await couple.second.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: question.id });
    expect(chat.thread_id).toBe(message.thread_id);
  });

  test("an unknown question has no rounds, and strangers are refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await couple.first.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: newUuid() })).toEqual({
      thread_id: null,
      questions: [],
      answer_details: [],
      reactions: [],
    });
    const stranger = await createSignedInUser(t);
    expect(
      await failure(stranger.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: newUuid() })),
    ).toEqual({ code: "42501", message: "active entitled couple access is required" });
  });

  test("hidden and deleted answers do not make a round", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const instanceId = await answeredRound(t, couple, question, { at: MARCH });
    await t.run(async (ctx) => {
      for (const answer of await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId))
        .collect()) {
        await ctx.db.patch(answer._id, answer.user_id === couple.first.userId ? { deleted_at: "2026-03-04T00:00:00.000Z" } : { moderation_status: "hidden" });
      }
    });
    const chat = await couple.first.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: question.id });
    expect(chat.questions).toEqual([]);
  });
});

describe("round info on question rows", () => {
  test("a repeat counts the earlier days the viewer answered and when the chat can start", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const marchInstance = await answeredRound(t, couple, question, { at: MARCH });
    const octoberInstance = await answeredRound(t, couple, question, { at: OCTOBER, answeredBy: [couple.first] });
    await answeredRound(t, couple, await seedQuestion(t), { at: OCTOBER });

    const rows = await couple.first.as.query(api.daily.get_daily_questions_history, {});
    const row = (instanceId: string) => rows.find((item) => item.instance_id === instanceId)!;
    expect(row(marchInstance)).toMatchObject({ earlier_round_count: 0, latest_earlier_round_local_date: null, chat_available: true });
    expect(row(octoberInstance)).toMatchObject({
      earlier_round_count: 1,
      latest_earlier_round_local_date: "2026-03-03",
      chat_available: true,
    });
    const single = rows.find((item) => item.question_id !== question.id)!;
    expect(single).toMatchObject({ earlier_round_count: 0, chat_available: true });
  });

  test("an earlier day the viewer did not answer is not a look back", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    await answeredRound(t, couple, question, { at: MARCH, answeredBy: [couple.second] });
    const october = await answeredRound(t, couple, question, { at: OCTOBER, answeredBy: [couple.first] });
    const rows = await couple.first.as.query(api.daily.get_daily_questions_history, {});
    expect(rows.find((item) => item.instance_id === october)).toMatchObject({
      earlier_round_count: 0,
      latest_earlier_round_local_date: null,
      chat_available: false,
    });
  });
});

describe("set_daily_answer_reaction", () => {
  const react = (user: TestUser, answerId: string, emoji: string | null) =>
    user.as.mutation(api.dailyQuestionChat.set_daily_answer_reaction, { p_answer_id: answerId, p_emoji: emoji });
  const reactionsSeenBy = async (user: TestUser, couple: TestCouple, questionId: string) =>
    (await user.as.query(api.dailyQuestionChat.get_daily_question_chat, { p_couple_id: couple.coupleId, p_question_id: questionId }))
      .reactions;

  test("a partner reacts to an answer, changes it, and takes it back, and both read it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const instanceId = await answeredRound(t, couple, question);
    const answerId = await answerIdOf(t, instanceId, couple.first);

    await react(couple.second, answerId.toUpperCase(), "❤️");
    const reaction = { answer_id: answerId, user_id: couple.second.userId, emoji: "❤️" };
    expect(await reactionsSeenBy(couple.first, couple, question.id)).toEqual([reaction]);
    expect(await reactionsSeenBy(couple.second, couple, question.id)).toEqual([reaction]);

    await react(couple.second, answerId, " 👍🏽 ");
    expect(await reactionsSeenBy(couple.first, couple, question.id)).toEqual([{ ...reaction, emoji: "👍🏽" }]);
    expect(await t.run((ctx) => ctx.db.query("daily_answer_reactions").collect())).toHaveLength(1);

    await react(couple.second, answerId, null);
    await react(couple.second, answerId, null);
    expect(await reactionsSeenBy(couple.first, couple, question.id)).toEqual([]);
  });

  test("a reaction on an answer the viewer can't read stays out of their chat", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const shared = await answeredRound(t, couple, question, { at: MARCH });
    await react(couple.second, await answerIdOf(t, shared, couple.first), "😂");
    // The question came back and only the first partner answered it.
    await answeredRound(t, couple, question, { at: OCTOBER, answeredBy: [couple.first] });
    expect((await reactionsSeenBy(couple.second, couple, question.id)).map((row) => row.emoji)).toEqual(["😂"]);
  });

  test("both partners can react to the same answer, their own included", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const instanceId = await answeredRound(t, couple, question);
    const answerId = await answerIdOf(t, instanceId, couple.first);
    await react(couple.first, answerId, "😂");
    await react(couple.second, answerId, "❤️");
    const seen = await reactionsSeenBy(couple.second, couple, question.id);
    expect(seen.map((row) => [row.user_id, row.emoji]).sort()).toEqual(
      [
        [couple.first.userId, "😂"],
        [couple.second.userId, "❤️"],
      ].sort(),
    );
  });

  test("a day you haven't answered and a hidden answer are refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const question = await seedQuestion(t);
    const shared = await answeredRound(t, couple, question, { at: MARCH });
    const onlyPartner = await answeredRound(t, couple, question, { at: OCTOBER, answeredBy: [couple.second] });
    expect(await failure(react(couple.first, await answerIdOf(t, onlyPartner, couple.second), "❤️"))).toEqual({
      code: "42501",
      message: "you must answer this daily question before reacting",
    });
    const partnerAnswer = await answerIdOf(t, shared, couple.second);
    await t.run(async (ctx) => {
      const row = await ctx.db.query("daily_question_answers").withIndex("by_uuid", (q) => q.eq("id", partnerAnswer)).unique();
      await ctx.db.patch(row!._id, { moderation_status: "hidden" });
    });
    expect(await failure(react(couple.first, partnerAnswer, "❤️"))).toEqual({
      code: "23514",
      message: "reaction target is not available",
    });
  });

  test.each([["a word", "love"], ["a digit", "1"], ["two emoji", "❤️👍"], ["nothing", "  "]])(
    "refuses %s as a reaction",
    async (_name, emoji) => {
      const t = newTest();
      const couple = await createCouple(t);
      const instanceId = await answeredRound(t, couple, await seedQuestion(t));
      expect(await failure(react(couple.second, await answerIdOf(t, instanceId, couple.first), emoji))).toEqual({
        code: "23514",
        message: "reaction must be one emoji",
      });
    },
  );

  test("strangers, former partners, and unknown answers are refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const instanceId = await answeredRound(t, couple, await seedQuestion(t));
    const answerId = await answerIdOf(t, instanceId, couple.first);
    const denied = { code: "42501", message: "active entitled couple access is required" };
    const stranger = await createSignedInUser(t);
    expect(await failure(react(stranger, answerId, "❤️"))).toEqual(denied);
    expect(await failure(react(couple.second, newUuid(), "❤️"))).toEqual(denied);
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(await failure(react(couple.second, answerId, "❤️"))).toEqual(denied);
    expect(await t.run((ctx) => ctx.db.query("daily_answer_reactions").collect())).toEqual([]);
  });
});
