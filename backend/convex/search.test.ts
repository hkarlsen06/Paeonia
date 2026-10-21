import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { answeredRound, seedQuestion } from "./dailyChat.setup";
import { newUuid } from "./lib/ids";
import { failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const MARCH = "2026-03-03T12:00:00.000Z";
const OCTOBER = "2026-10-09T12:00:00.000Z";

const search = (user: TestUser, text: string, locale: "en" | "nb" = "en") =>
  user.as.query(api.search.search_couple_content, { p_query: text, p_locale: locale });

/** A round both partners answered, with the given texts. */
async function sharedRound(t: TestConvex, couple: TestCouple, key: string, first: string, second: string, at = OCTOBER) {
  const question = await seedQuestion(t, key);
  const instanceId = await answeredRound(t, couple, question, {
    at,
    texts: { [couple.first.userId]: first, [couple.second.userId]: second },
  });
  return { question, instanceId };
}

async function startQuestionChat(user: TestUser, couple: TestCouple, questionId: string, body: string) {
  const [row] = await user.as.mutation(api.threads.create_daily_question_thread_with_message, {
    ...op(),
    p_couple_id: couple.coupleId,
    p_question_id: questionId,
    p_body: body,
  });
  return row;
}

async function startMemoryChat(user: TestUser, body: string) {
  const memoryId = newUuid();
  await user.as.mutation(api.memories.create_memory, {
    ...op(),
    p_memory_id: memoryId,
    p_title: "Cabin weekend",
    p_memory_date: "2026-10-01",
    p_note_body: "note",
  });
  const [row] = await user.as.mutation(api.threads.create_memory_thread_with_message, {
    ...op(),
    p_memory_id: memoryId,
    p_body: body,
  });
  return { memoryId, threadId: row.thread_id, messageId: row.message_id };
}

/** `author` posts a story and `replier` starts its reply thread. */
async function startStoryReply(t: TestConvex, couple: TestCouple, author: TestUser, replier: TestUser, body: string) {
  const storyId = newUuid();
  const up = await uploadAsset(t, author, { ...photo(couple.coupleId, "story", "story_photo"), parentId: storyId });
  await author.as.mutation(api.stories.post_story, {
    p_story_id: storyId,
    p_media_asset_id: up.assetId,
    p_caption: "Sunset at the harbour",
    ...op(),
  });
  const [row] = await replier.as.mutation(api.threads.create_story_thread_with_message, {
    ...op(),
    p_story_id: storyId,
    p_body: body,
  });
  return { storyId, threadId: row.thread_id, messageId: row.message_id };
}

describe("search_couple_content access", () => {
  test("refuses a signed-out caller, a user without a couple, and a couple without a subscription", async () => {
    const t = newTest();
    const lonely = await createSignedInUser(t);
    const unpaid = await createCouple(t, { entitled: false });

    expect((await failure(t.query(api.search.search_couple_content, { p_query: "sunset", p_locale: "en" }))).code).toBe("42501");
    expect((await failure(search(lonely, "sunset"))).code).toBe("42501");
    expect((await failure(search(unpaid.first, "sunset"))).code).toBe("42501");
  });

  test("never returns another couple's answers, messages, questions or stories", async () => {
    const t = newTest();
    const mine = await createCouple(t);
    const theirs = await createCouple(t);
    for (const couple of [mine, theirs]) {
      const { question } = await sharedRound(t, couple, `harbour${couple === mine ? "mine" : "theirs"}`, "harbour sunset", "harbour dinner");
      await startQuestionChat(couple.first, couple, question.id, "harbour message");
      await t.run(async (ctx) => {
        await ctx.db.insert("story_chain_stories", {
          id: newUuid(),
          game_id: newUuid(),
          couple_id: couple.coupleId,
          story_number: 1,
          starter_user_id: couple.first.userId,
          state: "finished",
          lines: [{ id: newUuid(), number: 1, author_user_id: couple.first.userId, text: "A harbour at night", created_at: MARCH }],
          seen_by: [],
          title: "Harbour",
          finished_at: MARCH,
          created_at: MARCH,
          updated_at: MARCH,
        });
      });
    }

    const result = await search(mine.first, "harbour");
    expect(result.answers).toHaveLength(2);
    expect(result.messages).toHaveLength(1);
    expect(result.story_chain).toHaveLength(1);
    const memberIds = new Set([mine.first.userId, mine.second.userId]);
    expect(result.answers.every((row) => memberIds.has(row.author_user_id))).toBe(true);
    expect(result.messages.every((row) => memberIds.has(row.sender_user_id))).toBe(true);
    const mineStory = await t.run((ctx) =>
      ctx.db
        .query("story_chain_stories")
        .withIndex("by_couple_id_story_number", (q) => q.eq("couple_id", mine.coupleId))
        .unique(),
    );
    expect(result.story_chain.map((row) => row.story_id)).toEqual([mineStory!.id]);

    const theirResult = await search(theirs.second, "harbour");
    expect(theirResult.answers.every((row) => !memberIds.has(row.author_user_id))).toBe(true);
    expect(theirResult.messages.every((row) => !memberIds.has(row.sender_user_id))).toBe(true);
  });

  test("finds nothing for a query shorter than two letters", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await sharedRound(t, couple, "tinyq", "x marks the spot", "x");
    expect(await search(couple.first, "x")).toEqual({ questions: [], answers: [], messages: [], story_chain: [] });
    expect(await search(couple.first, "  !? ")).toEqual({ questions: [], answers: [], messages: [], story_chain: [] });
  });
});

describe("answers and the reveal rule", () => {
  test("shows a partner's answer only in a round the caller answered too", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    // March: both answered. October: only the partner answered, so the caller has not earned it.
    const { question } = await sharedRound(t, couple, "lanternq", "lantern walk", "lantern fair", MARCH);
    const hidden = await answeredRound(t, couple, question, {
      at: OCTOBER,
      answeredBy: [couple.second],
      texts: { [couple.second.userId]: "lantern secret" },
    });

    const result = await search(couple.first, "lantern");
    const snippets = result.answers.map((row) => row.snippet).sort();
    expect(snippets).toEqual(["lantern fair", "lantern walk"]);
    expect(result.answers.map((row) => row.instance_id)).not.toContain(hidden);
    // The partner reads their own October answer.
    const partnerResult = await search(couple.second, "lantern");
    expect(partnerResult.answers.map((row) => row.snippet)).toContain("lantern secret");
  });

  test("leaves out removed answers and questions whose page cannot open yet", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "kiteq", "kite day", "kite flying", MARCH);
    const removed = await answeredRound(t, couple, question, {
      at: OCTOBER,
      texts: { [couple.first.userId]: "kite again", [couple.second.userId]: "kite removed" },
    });
    const waiting = await seedQuestion(t, "kitewaiting");
    await answeredRound(t, couple, waiting, {
      at: OCTOBER,
      answeredBy: [couple.first],
      texts: { [couple.first.userId]: "kite alone" },
    });
    await t.run(async (ctx) => {
      const answer = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", removed).eq("user_id", couple.second.userId))
        .unique();
      await ctx.db.patch(answer!._id, { deleted_at: OCTOBER });
    });

    const result = await search(couple.first, "kite");
    expect(result.answers.map((row) => row.snippet).sort()).toEqual(["kite again", "kite day", "kite flying"]);
  });

  test("labels topic answers with the topic", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "topicq", "campfire story", "campfire song");
    await t.run(async (ctx) => {
      const questionRow = await ctx.db
        .query("questions")
        .withIndex("by_uuid", (q) => q.eq("id", question.id))
        .unique();
      const collection = await ctx.db
        .query("question_collections")
        .withIndex("by_uuid", (q) => q.eq("id", questionRow!.collection_id))
        .unique();
      await ctx.db.patch(collection!._id, { kind: "topic", key: "outdoors" });
      await ctx.db.insert("topic_catalog", {
        collection_id: collection!.id,
        key: "outdoors",
        sort_order: 1,
        private: false,
        title_en: "Outdoors",
        subtitle_en: "",
        title_nb: "Ute",
        subtitle_nb: "",
        questions: [],
      });
    });

    const english = await search(couple.first, "campfire");
    expect(english.answers.map((row) => [row.topic_key, row.topic_title])).toEqual([
      ["outdoors", "Outdoors"],
      ["outdoors", "Outdoors"],
    ]);
    expect((await search(couple.first, "campfire", "nb")).answers[0].topic_title).toBe("Ute");
  });
});

describe("questions", () => {
  test("finds a question the couple has talked about by its wording, in the caller's language", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "meadowq", "a", "b");
    await seedQuestion(t, "meadowunseen");
    await t.run(async (ctx) => {
      const version = await ctx.db
        .query("question_version_localizations")
        .withIndex("by_question_version_id_locale", (q) => q.eq("question_version_id", question.versionId).eq("locale", "nb"))
        .unique();
      await ctx.db.patch(version!._id, { prompt: "Hva liker du best med enga" });
    });

    const english = await search(couple.first, "meadowq");
    expect(english.questions.map((row) => row.question_id)).toEqual([question.id]);
    expect(english.questions[0]).toMatchObject({ prompt: "meadowq prompt en", round_count: 1, local_date: "2026-10-09" });
    expect((await search(couple.first, "meadowunseen")).questions).toEqual([]);

    const norwegian = await search(couple.second, "enga", "nb");
    expect(norwegian.questions.map((row) => row.question_id)).toEqual([question.id]);
    expect((await search(couple.second, "enga", "en")).questions).toEqual([]);
  });
});

describe("chat messages", () => {
  test("finds messages in question chats and memory chats and says where they belong", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "pierq", "a", "b");
    const questionChat = await startQuestionChat(couple.second, couple, question.id, "Remember the pier at dusk?");
    const memoryChat = await startMemoryChat(couple.first, "The pier was freezing");

    const result = await search(couple.first, "pier");
    expect(result.messages).toHaveLength(2);
    const daily = result.messages.find((row) => row.thread_kind === "daily_question")!;
    expect(daily).toMatchObject({
      message_id: questionChat.message_id,
      question_id: question.id,
      memory_id: null,
      sender_user_id: couple.second.userId,
      snippet: "Remember the pier at dusk?",
    });
    const memory = result.messages.find((row) => row.thread_kind === "memory")!;
    expect(memory).toMatchObject({
      message_id: memoryChat.messageId,
      memory_id: memoryChat.memoryId,
      question_id: null,
      context_title: "Cabin weekend",
    });
  });

  test("leaves out deleted messages, hidden threads and chats of deleted memories", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "dockq", "a", "b");
    const questionChat = await startQuestionChat(couple.first, couple, question.id, "dock memories");
    const memoryChat = await startMemoryChat(couple.first, "dock photos");

    await t.run(async (ctx) => {
      const message = await ctx.db
        .query("thread_messages")
        .withIndex("by_uuid", (q) => q.eq("id", questionChat.message_id))
        .unique();
      await ctx.db.patch(message!._id, { deleted_at: OCTOBER });
    });
    expect((await search(couple.first, "dock")).messages.map((row) => row.message_id)).toEqual([memoryChat.messageId]);

    await t.run(async (ctx) => {
      const memory = await ctx.db
        .query("memories")
        .withIndex("by_uuid", (q) => q.eq("id", memoryChat.memoryId))
        .unique();
      await ctx.db.patch(memory!._id, { deleted_at: OCTOBER });
    });
    expect((await search(couple.first, "dock")).messages).toEqual([]);
  });

  test("finds replies to a story and says which story they belong to", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const reply = await startStoryReply(t, couple, couple.first, couple.second, "That harbour light is unreal");

    const result = await search(couple.first, "harbour");
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0]).toMatchObject({
      message_id: reply.messageId,
      thread_id: reply.threadId,
      thread_kind: "story",
      story_id: reply.storyId,
      question_id: null,
      memory_id: null,
      sender_user_id: couple.second.userId,
      context_title: "Sunset at the harbour",
    });
    // The story is the author's own to delete, and its replies go with it.
    await couple.first.as.mutation(api.stories.delete_story, { ...op(), p_story_id: reply.storyId });
    expect((await search(couple.first, "harbour")).messages).toEqual([]);
  });

  test("never finds a message its sender took back, or another couple's replies", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "unsendq", "a", "b");
    const questionChat = await startQuestionChat(couple.first, couple, question.id, "secret lighthouse plan");
    const memoryChat = await startMemoryChat(couple.second, "lighthouse photos");
    const storyReply = await startStoryReply(t, couple, couple.first, couple.second, "lighthouse at night");
    expect((await search(couple.first, "lighthouse")).messages).toHaveLength(3);

    await couple.first.as.mutation(api.threads.delete_thread_message, { ...op(), p_message_id: questionChat.message_id });
    await couple.second.as.mutation(api.threads.delete_thread_message, { ...op(), p_message_id: memoryChat.messageId });
    await couple.second.as.mutation(api.threads.delete_thread_message, { ...op(), p_message_id: storyReply.messageId });
    for (const user of [couple.first, couple.second]) {
      expect((await search(user, "lighthouse")).messages).toEqual([]);
      expect((await search(user, "secret")).messages).toEqual([]);
    }

    const other = await createCouple(t);
    expect((await search(other.first, "lighthouse")).messages).toEqual([]);
  });

  test("finds an edited message by its new text only", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { question } = await sharedRound(t, couple, "editq", "a", "b");
    const chat = await startQuestionChat(couple.first, couple, question.id, "ferry tickets");
    await couple.first.as.mutation(api.threads.edit_thread_message, {
      p_message_id: chat.message_id,
      p_body: "train tickets",
    });
    expect((await search(couple.first, "ferry")).messages).toEqual([]);
    expect((await search(couple.first, "train")).messages.map((row) => row.message_id)).toEqual([chat.message_id]);
  });
});
