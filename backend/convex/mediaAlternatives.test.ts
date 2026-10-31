import type { FunctionArgs } from "convex/server";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { currentQuestionFor, insertAnswerAsset, seedCatalog, textQuestions } from "./daily.setup";
import { newUuid } from "./lib/ids";
import { endCouple, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

type Target = FunctionArgs<typeof api.media.update_accessibility_text>["p_target"];
const NOW = "2026-10-10T12:00:00.000Z";
beforeEach(() => { setMediaEnv(); vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(new Date(NOW)); });
afterEach(() => vi.useRealTimers());

async function setup(kind: Target["kind"]) {
  const t = newTest();
  const couple = await createCouple(t);
  const fixture = kind === "chat" ? await chat(t, couple) : kind === "story" ? await story(t, couple) : await daily(t, couple);
  return { t, couple, ...fixture };
}

async function chat(t: TestConvex, couple: TestCouple) {
  const memoryId = newUuid();
  await couple.first.as.mutation(api.memories.create_memory, {
    ...op(), p_memory_id: memoryId, p_title: "Test memory", p_memory_date: "2026-10-01", p_note_body: "Test note",
  });
  const [thread] = await couple.first.as.mutation(api.threads.create_memory_thread_with_message, {
    ...op(), p_memory_id: memoryId, p_body: "Unchanged message",
  });
  const upload = await uploadAsset(t, couple.first, photo(couple.coupleId, "thread_message_media", "thread_media"));
  await couple.first.as.mutation(api.threads.send_thread_message, {
    ...op(), p_thread_id: thread.thread_id, p_body: "Unchanged caption", p_media_asset_ids: [upload.assetId],
  });
  const target: Target = { kind: "chat", message_id: upload.parentId, media_asset_id: upload.assetId };
  const read = () => couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: thread.thread_id, p_limit: 50 });
  const remove = () => couple.first.as.mutation(api.threads.delete_thread_message, { ...op(), p_message_id: upload.parentId });
  return { target, read, remove, assetId: upload.assetId };
}

async function story(t: TestConvex, couple: TestCouple) {
  const storyId = newUuid();
  const upload = await uploadAsset(t, couple.first, { ...photo(couple.coupleId, "story", "story_photo"), parentId: storyId });
  await couple.first.as.mutation(api.stories.post_story, {
    ...op(), p_story_id: storyId, p_media_asset_id: upload.assetId, p_caption: "Unchanged caption",
  });
  const target: Target = { kind: "story", story_id: storyId };
  const read = () => couple.second.as.query(api.stories.get_stories, {});
  const remove = () => couple.first.as.mutation(api.stories.delete_story, { ...op(), p_story_id: storyId });
  return { target, read, remove, assetId: upload.assetId };
}

async function daily(t: TestConvex, couple: TestCouple) {
  await seedCatalog(t, textQuestions(1).map(item => ({ ...item, kinds: ["text", "voice"] })));
  await couple.first.as.mutation(api.daily.start_daily_challenge_snapshot, op());
  const question = await currentQuestionFor(t, couple.first.userId);
  const answerId = newUuid();
  const assetId = await insertAnswerAsset(t, {
    ownerUserId: couple.first.userId, coupleId: couple.coupleId, answerId, mediaType: "voice",
  });
  await couple.first.as.mutation(api.daily.submit_daily_answer, {
    ...op(), p_instance_id: question.id,
    p_payload: { answer_id: answerId, media_asset_ids: [assetId], media_accessibility_text: "Original transcript" },
  });
  const target: Target = { kind: "daily", answer_id: answerId };
  const read = () => couple.second.as.query(api.daily.get_daily_answer_details, { p_couple_day_id: question.couple_day_id! });
  const remove = () => t.run(async ctx => {
    const answer = await ctx.db.query("daily_question_answers").withIndex("by_uuid", q => q.eq("id", answerId)).unique();
    await ctx.db.patch(answer!._id, { deleted_at: NOW });
  });
  return { target, read, remove, assetId, question };
}

describe("correcting authored media alternatives", () => {
  test.each(["chat", "story", "daily"] as const)("%s refuses partner, outsider and unauthenticated writes", async kind => {
    const { t, couple, target } = await setup(kind);
    const outsider = await createSignedInUser(t);
    const args = { ...op(), p_target: target, p_text: "private correction" };
    for (const user of [couple.second, outsider]) {
      await expect(user.as.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
    }
    await expect(t.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
  });

  test.each(["chat", "story", "daily"] as const)("%s checks live reference and access even on replay", async kind => {
    const { t, couple, target, remove } = await setup(kind);
    const args = { ...op(), p_target: target, p_text: "Corrected text" };
    await couple.first.as.mutation(api.media.update_accessibility_text, args);
    await remove();
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
    await endCouple(t, couple.coupleId, couple.first.userId);
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, { ...args, ...op() })).rejects.toThrow(/42501/);
  });

  test.each(["chat", "story", "daily"] as const)("%s refuses a replay after the owner leaves", async kind => {
    const { t, couple, target } = await setup(kind);
    const args = { ...op(), p_target: target, p_text: "Corrected text" };
    await couple.first.as.mutation(api.media.update_accessibility_text, args);
    await endCouple(t, couple.coupleId, couple.first.userId);
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, args)).rejects.toThrow(/42501/);
  });

  test.each(["chat", "story"] as const)("%s corrects, clears and prevents a late retry from replacing newer text", async kind => {
    const { couple, target, read } = await setup(kind);
    const earlier = { ...op(), p_target: target, p_text: "Earlier" };
    const newer = { ...op(), p_target: target, p_text: "  Corrected description  " };
    await couple.first.as.mutation(api.media.update_accessibility_text, newer);
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, earlier))
      .resolves.toEqual({ accessibility_text: "Corrected description" });
    expect(JSON.stringify(await read())).toContain("Corrected description");
    expect(JSON.stringify(await read())).toContain("Unchanged caption");
    await couple.first.as.mutation(api.media.update_accessibility_text, { ...op(), p_target: target, p_text: " " });
    expect(JSON.stringify(await read())).not.toContain("Corrected description");
  });

  test("daily corrections preserve all reveal reads, answer time and sent content, including after reveal", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { target, question, assetId, read } = await daily(t, couple);
    const correction = { ...op(), p_target: target, p_text: "Corrected private transcript. A bird sings." };
    await couple.first.as.mutation(api.media.update_accessibility_text, correction);
    const hidden = [
      await read(),
      await couple.second.as.query(api.daily.get_daily_answer_history_details, {}),
      await couple.second.as.query(api.daily.get_today_daily_challenge_snapshot, {}),
      await couple.second.as.query(api.dailyQuestionChat.get_daily_question_chat, {
        p_couple_id: couple.coupleId, p_question_id: question.question_id,
      }),
    ];
    expect(JSON.stringify(hidden)).not.toContain(correction.p_text);
    await couple.second.as.mutation(api.daily.submit_daily_answer, {
      ...op(), p_instance_id: question.id, p_payload: { text: "My answer" },
    });
    vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
    await couple.first.as.mutation(api.media.update_accessibility_text, { ...op(), p_target: target, p_text: "Corrected after reveal" });
    expect((await read()).find(row => row.answer_id === (target.kind === "daily" ? target.answer_id : "")))
      .toMatchObject({ media_accessibility_text: "Corrected after reveal", answered_at: NOW, media_asset_ids: [assetId], text_body: null });
  });

  test("rejects overlong corrections and deleted media without changing the stored text", async () => {
    const { t, couple, target, assetId } = await setup("story");
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, {
      ...op(), p_target: target, p_text: "x".repeat(10001),
    })).rejects.toThrow(/23514/);
    await t.run(async ctx => {
      const asset = await ctx.db.query("media_assets").withIndex("by_uuid", q => q.eq("id", assetId)).unique();
      await ctx.db.patch(asset!._id, { deleted_at: NOW });
    });
    await expect(couple.first.as.mutation(api.media.update_accessibility_text, {
      ...op(), p_target: target, p_text: "Do not restore deleted media",
    })).rejects.toThrow(/42501/);
  });
});
