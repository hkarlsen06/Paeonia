import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { nowIso } from "./lib/time";
import { failure, op, setMediaEnv } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const HOUR = 60 * 60 * 1000;
const advance = (ms: number) => vi.setSystemTime(new Date(Date.now() + ms));

type SeededTopic = { key: string; collectionId: string; questionIds: string[] };

/** An active topic with `count` active text questions named `<key>_q1` and so on. */
async function seedTopic(
  t: TestConvex,
  key: string,
  options: { count?: number; sortOrder?: number; adultsOnly?: boolean } = {},
): Promise<SeededTopic> {
  return await t.run(async (ctx) => {
    const now = nowIso();
    const collectionId = newUuid();
    await ctx.db.insert("question_collections", {
      id: collectionId,
      kind: "topic",
      key,
      sort_order: options.sortOrder ?? 1,
      adults_only: options.adultsOnly ?? false,
      status: "active",
      created_at: now,
      updated_at: now,
    });
    for (const locale of ["en", "nb"] as const) {
      await ctx.db.insert("question_collection_localizations", {
        collection_id: collectionId,
        locale,
        title: `${key} ${locale}`,
        subtitle: `${key} subtitle ${locale}`,
        created_at: now,
        updated_at: now,
      });
    }
    const questionIds: string[] = [];
    for (let index = 1; index <= (options.count ?? 3); index += 1) {
      const id = newUuid();
      const versionId = newUuid();
      await ctx.db.insert("questions", {
        id,
        collection_id: collectionId,
        key: `${key}_q${index}`,
        status: "active",
        resurfaceable: false,
        sort_order: index,
        created_at: now,
        updated_at: now,
      });
      await ctx.db.insert("question_versions", {
        id: versionId,
        question_id: id,
        version_number: 1,
        status: "active",
        active_from: now,
        created_at: now,
      });
      for (const locale of ["en", "nb"] as const) {
        await ctx.db.insert("question_version_localizations", {
          question_version_id: versionId,
          locale,
          prompt: `${key} secret prompt ${index} ${locale}`,
          short_prompt: `${key} short ${index} ${locale}`,
          created_at: now,
          updated_at: now,
        });
      }
      await ctx.db.insert("question_answer_kinds", { question_version_id: versionId, answer_kind: "text", created_at: now });
      questionIds.push(id);
    }
    return { key, collectionId, questionIds };
  });
}

const answer = (user: TestUser, questionId: string, text = "an answer", instanceId = newUuid()) =>
  user.as.mutation(api.topics.submit_topic_answer, {
    ...op(),
    p_question_id: questionId,
    p_instance_id: instanceId,
    p_payload: { text },
  });

const overview = (user: TestUser) => user.as.query(api.topics.get_topics_overview, {});
const topicOf = (user: TestUser, key: string) => user.as.query(api.topics.get_topic, { p_topic_key: key });
const skip = (user: TestUser, questionId: string, skipped = true) =>
  user.as.mutation(api.topics.set_topic_question_skipped, { p_question_id: questionId, p_skipped: skipped });
const setAdult = (user: TestUser, status: "confirmed" | "hidden") =>
  user.as.mutation(api.topics.set_adult_topics_status, { p_status: status });

async function setup() {
  const t = newTest();
  const couple = await createCouple(t);
  return { t, couple, a: couple.first, b: couple.second };
}

async function openAdults(couple: TestCouple) {
  await setAdult(couple.first, "confirmed");
  await setAdult(couple.second, "confirmed");
}

describe("overview", () => {
  test("lists topics in shelf order with the couple's counts", async () => {
    const { t, a, b } = await setup();
    const later = await seedTopic(t, "later", { sortOrder: 2, count: 2 });
    const first = await seedTopic(t, "first", { sortOrder: 1, count: 4 });
    await answer(a, first.questionIds[0]);
    await answer(b, first.questionIds[0]);
    await answer(b, first.questionIds[1]);
    await answer(a, first.questionIds[2]);

    const result = await overview(a);
    expect(result.adult_topics_hidden_by_viewer).toBe(false);
    expect(result.topics.map((topic) => topic.topic_key)).toEqual(["first", "later"]);
    expect(result.topics[0]).toMatchObject({
      title_en: "first en",
      title_nb: "first nb",
      adult_state: "open",
      total_count: 4,
      together_count: 1,
      for_you_count: 1,
      waiting_for_partner_count: 1,
    });
    expect(result.topics[1]).toMatchObject({ topic_key: later.key, total_count: 2, together_count: 0 });
  });

  test("a skipped question leaves the total and shows as skipped, for both partners", async () => {
    const { t, a, b } = await setup();
    const topic = await seedTopic(t, "travel", { count: 3 });
    await skip(a, topic.questionIds[1]);
    await skip(a, topic.questionIds[1]);
    expect((await overview(b)).topics[0].total_count).toBe(2);
    const rows = (await topicOf(b, "travel")).questions;
    expect(rows.map((row) => row.is_skipped)).toEqual([false, true, false]);
    expect(await t.run((ctx) => ctx.db.query("topic_question_skips").collect())).toHaveLength(1);

    await skip(b, topic.questionIds[1], false);
    expect((await overview(a)).topics[0].total_count).toBe(3);
  });
});

describe("answering", () => {
  test("the first answer starts the question and the partner joins the same instance", async () => {
    const { t, a, b } = await setup();
    const topic = await seedTopic(t, "know");
    const sentId = newUuid();
    const first = await answer(a, topic.questionIds[0], "mine", sentId);
    expect(first.instance_id).toBe(sentId);
    const second = await answer(b, topic.questionIds[0], "theirs");
    expect(second.instance_id).toBe(sentId);

    const instances = await t.run((ctx) => ctx.db.query("daily_question_instances").collect());
    expect(instances).toHaveLength(1);
    expect(instances[0]).toMatchObject({
      seeded_for_user_id: a.userId,
      topic_collection_id: topic.collectionId,
      slot_number: 0,
      status: "answered",
    });
    expect(instances[0].couple_day_id).toBeUndefined();
    expect(instances[0].started_couple_day_id).toBeDefined();

    expect(await failure(answer(a, topic.questionIds[0], "again"))).toMatchObject({ code: "23505" });
  });

  test("the partner's answer shows only after the viewer answers", async () => {
    const { t, a, b } = await setup();
    const topic = await seedTopic(t, "know");
    await answer(a, topic.questionIds[0], "a's words");

    const before = await topicOf(b, "know");
    const row = before.questions[0].row!;
    expect(row).toMatchObject({ topic_key: "know", own_answer_id: null, can_view_partner_answer: false, chat_available: false });
    expect(before.answer_details).toHaveLength(1);
    expect(before.answer_details[0]).toMatchObject({ can_view_answer: false, text_body: null });
    expect(before.questions[1].row).toBeNull();

    await answer(b, topic.questionIds[0], "b's words");
    const after = await topicOf(b, "know");
    expect(after.questions[0].row).toMatchObject({ can_view_partner_answer: true, chat_available: true });
    expect(after.answer_details.map((detail) => detail.text_body).sort()).toEqual(["a's words", "b's words"]);
  });

  test("answering a skipped question brings it back", async () => {
    const { t, a } = await setup();
    const topic = await seedTopic(t, "know");
    await skip(a, topic.questionIds[0]);
    await answer(a, topic.questionIds[0]);
    expect(await t.run((ctx) => ctx.db.query("topic_question_skips").collect())).toHaveLength(0);
  });

  test("topic answers count for the streak but never complete the daily questions or reach their history", async () => {
    const { t, a, b } = await setup();
    const topic = await seedTopic(t, "know");
    await answer(a, topic.questionIds[0]);
    await answer(b, topic.questionIds[0]);

    const events = await t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.map((event) => event.activity_kind)).toEqual(["topic_answer_submitted", "topic_answer_submitted"]);
    expect(await t.run((ctx) => ctx.db.query("daily_challenges").collect())).toHaveLength(0);
    expect(await t.run((ctx) => ctx.db.query("streak_states").collect())).toMatchObject([{ current_count: 1 }]);
    expect(await a.as.query(api.daily.get_daily_questions_history, {})).toEqual([]);
    expect(await a.as.query(api.daily.get_daily_answer_history_details, {})).toEqual([]);
  });

  test("a topic question can't be answered through the daily answer function", async () => {
    const { t, a } = await setup();
    const topic = await seedTopic(t, "know");
    const { instance_id } = await answer(a, topic.questionIds[0]);
    expect(
      await failure(
        a.as.mutation(api.daily.submit_daily_answer, { ...op(), p_instance_id: instance_id, p_payload: { text: "x" } }),
      ),
    ).toMatchObject({ code: "23514" });
  });
});

describe("adult topics", () => {
  test("locked, then waiting for the partner, then open", async () => {
    const { t, a, b } = await setup();
    const flirt = await seedTopic(t, "flirt", { adultsOnly: true });
    expect((await overview(a)).topics[0]).toMatchObject({ topic_key: "flirt", adult_state: "locked" });
    expect(await failure(topicOf(a, "flirt"))).toEqual({ code: "42501", message: "adult topic is not open" });
    expect(await failure(answer(a, flirt.questionIds[0]))).toEqual({ code: "42501", message: "adult topic is not open" });
    expect(await failure(skip(a, flirt.questionIds[0]))).toMatchObject({ code: "42501" });

    await setAdult(a, "confirmed");
    expect((await overview(a)).topics[0].adult_state).toBe("waiting_for_partner");
    expect((await overview(b)).topics[0].adult_state).toBe("locked");

    await setAdult(b, "confirmed");
    expect((await overview(b)).topics[0].adult_state).toBe("open");
    expect((await topicOf(b, "flirt")).questions).toHaveLength(3);
    await answer(b, flirt.questionIds[0]);
  });

  test("a hidden adult topic is gone for both, and only the hider is told it can come back", async () => {
    const { t, a, b } = await setup();
    await seedTopic(t, "know", { sortOrder: 1 });
    const flirt = await seedTopic(t, "flirt", { adultsOnly: true, sortOrder: 2 });
    await setAdult(a, "confirmed");
    await setAdult(b, "hidden");

    const forB = await overview(b);
    expect(forB.topics.map((topic) => topic.topic_key)).toEqual(["know"]);
    expect(forB.adult_topics_hidden_by_viewer).toBe(true);
    const forA = await overview(a);
    expect(forA.topics.map((topic) => topic.topic_key)).toEqual(["know"]);
    expect(forA.adult_topics_hidden_by_viewer).toBe(false);
    expect(await failure(answer(a, flirt.questionIds[0]))).toMatchObject({ code: "42501" });

    await setAdult(b, "confirmed");
    expect((await overview(a)).topics.map((topic) => topic.adult_state)).toEqual(["open", "open"]);
  });
});

describe("pushes", () => {
  test("one push per 3 hours, only while something waits, and it never names the topic or the question", async () => {
    const { t, a, b } = await setup();
    await addDevice(t, b.userId, { locale: "en", token: "b" });
    const topic = await seedTopic(t, "travel", { count: 4 });

    await answer(a, topic.questionIds[0]);
    await answer(a, topic.questionIds[1]);
    let rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      kind: "topics_waiting",
      recipient_user_id: b.userId,
      title: "New answers from First Partner",
      body: "Open Paeonia to see what's waiting.",
      apns_collapse_id: `topics:${(await t.run((ctx) => ctx.db.query("couples").first()))!.id}`,
    });
    expect(JSON.stringify(rows[0])).not.toMatch(/travel|secret prompt|short/);
    expect(await deliverDuePushes(t)).toHaveLength(1);

    // Inside the window: the next push waits for the window to end.
    advance(HOUR);
    await answer(a, topic.questionIds[2]);
    rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(rows).toHaveLength(2);
    const later = rows.find((row) => row.sent_at === undefined)!;
    expect(Date.parse(later.scheduled_for) - Date.parse(rows.find((row) => row.sent_at !== undefined)!.scheduled_for)).toBe(3 * HOUR);

    // A pending push already covers more answers.
    await answer(a, topic.questionIds[3]);
    expect(await t.run((ctx) => ctx.db.query("notification_outbox").collect())).toHaveLength(2);

    // b answers everything before it is due, so the send drops it.
    for (const questionId of topic.questionIds) await answer(b, questionId);
    await t.run(async (ctx) => {
      for (const instance of await ctx.db.query("daily_question_instances").collect()) {
        await ctx.db.insert("daily_answer_seen_states", {
          instance_id: instance.id,
          couple_id: instance.couple_id,
          user_id: b.userId,
          seen_at: nowIso(),
        });
      }
    });
    advance(3 * HOUR);
    expect(await deliverDuePushes(t)).toHaveLength(0);
    const dropped = (await t.run((ctx) => ctx.db.query("notification_outbox").collect())).find((row) => row.id === later.id)!;
    expect(dropped.last_error).toBe("notification is out of date");
  });

  test("a Flirt chat message pushes only who wrote, with no body, no message and no prompt", async () => {
    const { t, couple, a, b } = await setup();
    await addDevice(t, b.userId, { locale: "en", token: "b" });
    const flirt = await seedTopic(t, "flirt", { adultsOnly: true });
    await openAdults(couple);
    await answer(a, flirt.questionIds[0]);
    await answer(b, flirt.questionIds[0]);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });

    await a.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_couple_id: couple.coupleId,
      p_question_id: flirt.questionIds[0],
      p_body: "Very flirty words",
    });
    const rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ kind: "thread_message_sent", title: "New message from First Partner" });
    expect(rows[0].body).toBeUndefined();
    const stored = JSON.stringify(rows[0]);
    expect(stored).not.toContain("Very flirty words");
    expect(stored).not.toContain("secret prompt");
    expect(stored).not.toContain("short 1");
    expect(stored).not.toContain("flirt");

    const threads = await b.as.query(api.threads.get_conversation_threads, {});
    expect(threads[0]).toMatchObject({ topic_key: "flirt", adults_only: true });

    // Once the topic is hidden, its chat is closed too.
    await setAdult(b, "hidden");
    expect(await b.as.query(api.threads.get_conversation_threads, {})).toEqual([]);
    expect(
      await failure(
        b.as.query(api.dailyQuestionChat.get_daily_question_chat, {
          p_couple_id: couple.coupleId,
          p_question_id: flirt.questionIds[0],
        }),
      ),
    ).toMatchObject({ code: "42501" });
  });
});

describe("a Flirt topic that closes", () => {
  /** Opens Flirt, has both partners answer its first question, and starts its chat with one message. */
  async function flirtWithChat() {
    const { t, couple, a, b } = await setup();
    await addDevice(t, b.userId, { locale: "en", token: "b" });
    const flirt = await seedTopic(t, "flirt", { adultsOnly: true });
    await openAdults(couple);
    const first = await answer(a, flirt.questionIds[0], "a flirty answer");
    await answer(b, flirt.questionIds[0], "b flirty answer");
    const [chat] = await a.as.mutation(api.threads.create_daily_question_thread_with_message, {
      ...op(),
      p_couple_id: couple.coupleId,
      p_question_id: flirt.questionIds[0],
      p_body: "hello there",
    });
    return { t, couple, a, b, flirt, first, chat };
  }

  test("closes its chat messages, message edits and chat photos", async () => {
    const { t, couple, a, b, chat } = await flirtWithChat();
    const assetId = await t.run(async (ctx) => {
      const id = newUuid();
      const now = nowIso();
      await ctx.db.insert("media_assets", {
        id,
        owner_user_id: a.userId,
        couple_id: couple.coupleId,
        reserved_parent_kind: "thread_message_media",
        reserved_parent_id: chat.message_id,
        reserved_by_client_operation_id: newUuid(),
        bucket: "couple-media",
        storage_path: `${couple.coupleId}/${id}`,
        media_type: "image",
        upload_purpose: "thread_media",
        expected_media_type: "image",
        expected_bucket: "couple-media",
        upload_status: "finalized",
        upload_expires_at: now,
        upload_finalized_at: now,
        moderation_status: "visible",
        storage_delete_status: "none",
        storage_delete_attempts: 0,
        created_at: now,
        updated_at: now,
      });
      await ctx.db.insert("thread_message_media", { message_id: chat.message_id, media_asset_id: id, sort_order: 1 });
      return id;
    });
    const signedUrl = (user: TestUser) =>
      user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: assetId, p_expires_in_seconds: 300 });
    expect(await signedUrl(b)).toHaveLength(1);
    expect((await b.as.query(api.threads.get_thread_messages, { p_thread_id: chat.thread_id, p_limit: 50 })).messages).toHaveLength(1);

    await setAdult(b, "hidden");
    const closed = { code: "42501", message: "adult topic is not open" };
    expect(await failure(b.as.query(api.threads.get_thread_messages, { p_thread_id: chat.thread_id, p_limit: 50 }))).toEqual(closed);
    expect(await failure(a.as.query(api.threads.get_thread_messages, { p_thread_id: chat.thread_id, p_limit: 50 }))).toEqual(closed);
    expect(
      await failure(a.as.mutation(api.threads.edit_thread_message, { p_message_id: chat.message_id, p_body: "edited" })),
    ).toEqual(closed);
    expect(await failure(a.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: chat.thread_id, p_body: "hi" }))).toEqual(closed);
    expect((await failure(signedUrl(b))).code).toBe("42501");
  });

  test("closes its answer photos and answer edits", async () => {
    const { t, couple, a, b } = await setup();
    const flirt = await seedTopic(t, "flirt", { adultsOnly: true });
    await openAdults(couple);
    const first = await answer(a, flirt.questionIds[0], "a flirty answer");
    // A photo on a's answer (Flirt questions never ask for one, but the gate must hold for any media).
    const assetId = await t.run(async (ctx) => {
      const id = newUuid();
      const now = nowIso();
      await ctx.db.insert("media_assets", {
        id,
        owner_user_id: a.userId,
        couple_id: couple.coupleId,
        reserved_parent_kind: "daily_answer_media",
        reserved_parent_id: first.answer_id,
        reserved_by_client_operation_id: newUuid(),
        bucket: "couple-media",
        storage_path: `${couple.coupleId}/${id}`,
        media_type: "image",
        upload_purpose: "daily_answer_media",
        expected_media_type: "image",
        expected_bucket: "couple-media",
        upload_status: "finalized",
        upload_expires_at: now,
        upload_finalized_at: now,
        moderation_status: "visible",
        storage_delete_status: "none",
        storage_delete_attempts: 0,
        created_at: now,
        updated_at: now,
      });
      await ctx.db.insert("daily_answer_media", { answer_id: first.answer_id, media_asset_id: id, sort_order: 1 });
      return id;
    });
    const signedUrl = () => a.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: assetId, p_expires_in_seconds: 300 });
    const edit = () =>
      a.as.mutation(api.daily.update_daily_answer_text, { ...op(), p_instance_id: first.instance_id, p_text: "changed" });
    expect(await signedUrl()).toHaveLength(1);
    await edit();

    await setAdult(b, "hidden");
    expect((await failure(signedUrl())).code).toBe("42501");
    expect(await failure(edit())).toEqual({ code: "42501", message: "adult topic is not open" });
  });

  test("a Flirt chat push queued before the topic closed is dropped when it is due", async () => {
    const { t, b } = await flirtWithChat();
    const queued = (await t.run((ctx) => ctx.db.query("notification_outbox").collect())).filter(
      (row) => row.kind === "thread_message_sent" && row.sent_at === undefined,
    );
    expect(queued).toHaveLength(1);
    await setAdult(b, "hidden");
    expect(await deliverDuePushes(t)).toEqual(
      expect.not.arrayContaining([expect.objectContaining({ outbox_id: queued[0].id })]),
    );
    const row = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(row.find((item) => item.id === queued[0].id)!.last_error).toBe("notification is out of date");
  });
});

describe("topic push spacing", () => {
  test("the next topic push waits 3 hours from when the last one really went out", async () => {
    const { t, a, b } = await setup();
    await addDevice(t, b.userId, { locale: "en", token: "b" });
    const topic = await seedTopic(t, "travel", { count: 3 });
    const start = Date.now();
    await answer(a, topic.questionIds[0]);

    // The send is retried and goes out two minutes late.
    advance(2 * 60 * 1000);
    expect(await deliverDuePushes(t)).toHaveLength(1);
    const sentAt = Date.now();

    advance(HOUR);
    await answer(a, topic.questionIds[1]);
    const pending = (await t.run((ctx) => ctx.db.query("notification_outbox").collect())).filter((row) => row.sent_at === undefined);
    expect(pending).toHaveLength(1);
    expect(Date.parse(pending[0].scheduled_for)).toBe(sentAt + 3 * HOUR);
    expect(Date.parse(pending[0].scheduled_for)).toBeGreaterThan(start + 3 * HOUR);
  });

  test("a topic push due less than 3 hours after another one went out is dropped", async () => {
    const { t, a, b } = await setup();
    await addDevice(t, b.userId, { locale: "en", token: "b" });
    const topic = await seedTopic(t, "travel", { count: 2 });
    await answer(a, topic.questionIds[0]);
    // A second row for another push, already due, as if two had been queued.
    await t.run(async (ctx) => {
      const original = (await ctx.db.query("notification_outbox").collect())[0];
      const { _id, _creationTime, ...rest } = original;
      void _id;
      void _creationTime;
      await ctx.db.insert("notification_outbox", {
        ...rest,
        id: newUuid(),
        dedupe_key: `${original.dedupe_key}:second`,
        scheduled_for: new Date(Date.parse(original.scheduled_for) - 1000).toISOString(),
      });
    });
    const delivered = await deliverDuePushes(t);
    expect(delivered).toHaveLength(1);
    const rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(rows.filter((row) => row.last_error === "notification is out of date")).toHaveLength(1);
  });
});
