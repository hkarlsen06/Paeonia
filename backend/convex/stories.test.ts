import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds = 60) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

/** Uploads a story photo reserved for `storyId`, the way the app does before it posts. */
const storyPhoto = (t: TestConvex, user: TestUser, coupleId: string, storyId: string) =>
  uploadAsset(t, user, { ...photo(coupleId, "story", "story_photo"), parentId: storyId });

async function post(
  t: TestConvex,
  couple: TestCouple,
  overrides: { user?: TestUser; storyId?: string; caption?: string | null; operation?: ReturnType<typeof op> } = {},
) {
  const user = overrides.user ?? couple.first;
  const storyId = overrides.storyId ?? newUuid();
  const up = await storyPhoto(t, user, couple.coupleId, storyId);
  const run = (assetId = up.assetId, caption = overrides.caption, operation = overrides.operation ?? op()) =>
    user.as.mutation(api.stories.post_story, {
      p_story_id: storyId,
      p_media_asset_id: assetId,
      ...(caption === undefined ? {} : { p_caption: caption }),
      ...operation,
    });
  return { storyId, up, run };
}

const getStories = (user: TestUser) => user.as.query(api.stories.get_stories, {});
const markSeen = (user: TestUser, id: string) => user.as.mutation(api.stories.mark_story_seen, { p_story_id: id });
const remove = (user: TestUser, id: string) => user.as.mutation(api.stories.delete_story, { p_story_id: id, ...op() });
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
const storyRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("stories").collect());
const assetRow = (t: TestConvex, id: string) =>
  t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", id)).unique());

describe("post_story and get_stories", () => {
  test("round trip: both partners see the story, newest first", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const older = await post(t, couple, { caption: "Thinking of you" });
    const olderRow = await older.run();
    expect(olderRow).toEqual({
      id: older.storyId,
      author_user_id: couple.first.userId,
      media_asset_id: older.up.assetId,
      caption: "Thinking of you",
      created_at: NOW,
      seen_at: null,
    });

    tick();
    const newer = await post(t, couple, { user: couple.second });
    const newerRow = await newer.run();
    expect(newerRow?.caption).toBeNull();

    for (const user of [couple.first, couple.second]) {
      const seen = await getStories(user);
      expect(seen.couple_id).toBe(couple.coupleId);
      expect(seen.stories.map((story) => story.id)).toEqual([newer.storyId, older.storyId]);
    }
  });

  test("accepts uppercase ids and stores them lowercase", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const story = await post(t, couple);
    const row = await couple.first.as.mutation(api.stories.post_story, {
      p_story_id: story.storyId.toUpperCase(),
      p_media_asset_id: story.up.assetId.toUpperCase(),
      ...op(),
    });
    expect(row?.id).toBe(story.storyId);
  });

  test("trims the caption, treats an empty one as none, and caps it at 200 code points", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await (await post(t, couple, { caption: "  hi  " })).run())?.caption).toBe("hi");
    expect((await (await post(t, couple, { caption: "   " })).run())?.caption).toBeNull();
    expect((await (await post(t, couple, { caption: null })).run())?.caption).toBeNull();

    const edge = "😀".repeat(200);
    expect(edge.length).toBe(400);
    expect((await (await post(t, couple, { caption: edge })).run())?.caption).toBe(edge);

    const tooLong = await post(t, couple, { caption: "😀".repeat(201) });
    expect((await failure(tooLong.run())).code).toBe("23514");
    expect(await storyRows(t)).toHaveLength(4);
  });

  test("a replay of the same operation returns the same row, also after the partner saw it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const operation = op();
    const story = await post(t, couple, { caption: "Hello", operation });
    const first = await story.run();
    await markSeen(couple.second, story.storyId);
    tick();
    const again = await story.run(story.up.assetId, "Hello", operation);
    expect(again).toEqual({ ...first, seen_at: NOW });
    expect(await storyRows(t)).toHaveLength(1);
  });

  test("a new operation for a story the author already posted returns it and queues no second push", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const story = await post(t, couple);
    const first = await story.run();
    const again = await story.run();
    expect(again).toEqual(first);
    expect(await storyRows(t)).toHaveLength(1);
    expect(await outbox(t)).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("refuses a story id that already belongs to another couple or another author", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const story = await post(t, couple);
    await story.run();

    const intruder = await post(t, other, { storyId: story.storyId });
    expect((await failure(intruder.run())).code).toBe("42501");

    const partner = await post(t, couple, { user: couple.second, storyId: story.storyId });
    expect((await failure(partner.run())).code).toBe("42501");
    expect((await storyRows(t))[0].author_user_id).toBe(couple.first.userId);
  });

  test("refuses media that does not fit the contract", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = newUuid();
    const own = await storyPhoto(t, couple.first, couple.coupleId, storyId);
    const send = (user: TestUser, assetId: string, id = storyId) =>
      failure(user.as.mutation(api.stories.post_story, { p_story_id: id, p_media_asset_id: assetId, ...op() }));

    // The partner owns the story photo, not the caller.
    expect((await send(couple.second, own.assetId)).code).toBe("42501");
    // An asset that does not exist.
    expect((await send(couple.first, newUuid())).code).toBe("42501");
    // A photo reserved for another story id.
    expect((await send(couple.first, own.assetId, newUuid())).code).toBe("23514");
    // A memory photo has the wrong purpose.
    const memoryPhoto = await uploadAsset(t, couple.first, { ...photo(couple.coupleId), parentId: storyId });
    expect((await send(couple.first, memoryPhoto.assetId)).code).toBe("23514");
    // A photo from another couple.
    const other = await createCouple(t);
    const foreign = await storyPhoto(t, other.first, other.coupleId, storyId);
    expect((await send(couple.first, foreign.assetId)).code).toBe("42501");
    // A pending upload.
    const [pending] = await couple.first.as.mutation(api.media.create_pending_media_upload, {
      ...op(),
      p_reserved_parent_kind: "story",
      p_reserved_parent_id: storyId,
      p_upload_purpose: "story_photo",
      p_media_type: "image",
      p_file_extension: "jpg",
      p_couple_id: couple.coupleId,
    });
    expect((await send(couple.first, pending.media_asset_id)).code).toBe("23514");
    expect(await storyRows(t)).toHaveLength(0);
  });

  test("refuses a user without a couple and a couple without a subscription", async () => {
    const t = newTest();
    const single = await createSignedInUser(t);
    expect((await failure(getStories(single))).code).toBe("42501");

    const lapsed = await createCouple(t, { entitled: false });
    expect((await failure(getStories(lapsed.first))).code).toBe("42501");
  });

  test("a non-member cannot post or read", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    expect((await failure(stranger.as.mutation(api.stories.post_story, {
      p_story_id: newUuid(),
      p_media_asset_id: newUuid(),
      ...op(),
    }))).code).toBe("42501");
    expect((await failure(markSeen(stranger, newUuid()))).code).toBe("42501");
    await post(t, couple);
  });

  test("the rate limit refuses the 31st post in an hour", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const attempts = [];
    for (let i = 0; i < 31; i += 1) attempts.push(await post(t, couple));
    for (const attempt of attempts.slice(0, 30)) await attempt.run();
    expect((await failure(attempts[30].run())).code).toBe("53300");
    expect(await storyRows(t)).toHaveLength(30);
  });
});

describe("story photo access", () => {
  test("the partner can sign the photo, and a non-member and a deleted story cannot", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const stranger = await createSignedInUser(t);
    const story = await post(t, couple);
    await story.run();
    const sign = (user: TestUser) =>
      user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: story.up.assetId });

    for (const user of [couple.first, couple.second]) {
      const [row] = await sign(user);
      expect(row).toMatchObject({ media_asset_id: story.up.assetId, bucket: "couple-media" });
      expect(row.signed_url).toContain("/media?asset=");
    }
    expect((await failure(sign(stranger))).code).toBe("42501");

    await remove(couple.first, story.storyId);
    expect((await failure(sign(couple.second))).code).toBe("42501");
  });

  test("the photo cannot be read before a story points at it", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const up = await storyPhoto(t, couple.first, couple.coupleId, newUuid());
    const error = await failure(
      couple.second.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId }),
    );
    expect(error.code).toBe("42501");
  });
});

describe("delete_story", () => {
  test("only the author deletes, the story leaves the list, and its photo is queued for deletion", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const story = await post(t, couple);
    await story.run();

    expect((await failure(remove(couple.second, story.storyId))).code).toBe("42501");
    expect((await getStories(couple.second)).stories).toHaveLength(1);
    expect((await assetRow(t, story.up.assetId))?.storage_delete_status).toBe("none");

    expect(await remove(couple.first, story.storyId)).toBeNull();
    expect((await getStories(couple.first)).stories).toEqual([]);
    expect((await getStories(couple.second)).stories).toEqual([]);
    const asset = await assetRow(t, story.up.assetId);
    expect(asset?.storage_delete_status).toBe("pending");
    expect(asset?.deleted_at).toBe(NOW);
    expect((await storyRows(t))[0].deleted_at).toBe(NOW);
  });

  test("a missing or already deleted story is fine", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await remove(couple.first, newUuid())).toBeNull();
    const story = await post(t, couple);
    await story.run();
    await remove(couple.first, story.storyId);
    expect(await remove(couple.first, story.storyId)).toBeNull();
    expect(await remove(couple.second, story.storyId)).toBeNull();
  });

  test("a retry of the post after the delete does not bring the story back", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const story = await post(t, couple);
    await story.run();
    await remove(couple.first, story.storyId);
    expect(await story.run()).toBeNull();
    expect((await getStories(couple.first)).stories).toEqual([]);
  });
});

describe("mark_story_seen", () => {
  test("the partner's first view is kept, and the author's own view changes nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const story = await post(t, couple);
    await story.run();

    expect(await markSeen(couple.first, story.storyId)).toBeNull();
    expect((await getStories(couple.first)).stories[0].seen_at).toBeNull();

    expect(await markSeen(couple.second, story.storyId)).toBeNull();
    expect((await getStories(couple.first)).stories[0].seen_at).toBe(NOW);

    tick(3600);
    await markSeen(couple.second, story.storyId.toUpperCase());
    expect((await getStories(couple.first)).stories[0].seen_at).toBe(NOW);
  });

  test("a missing or deleted story is a no-op, and another couple's story is refused", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    expect(await markSeen(couple.second, newUuid())).toBeNull();

    const story = await post(t, couple);
    await story.run();
    expect((await failure(markSeen(other.second, story.storyId))).code).toBe("42501");
    await remove(couple.first, story.storyId);
    expect(await markSeen(couple.second, story.storyId)).toBeNull();
    expect((await storyRows(t))[0].seen_at).toBeUndefined();
  });
});

describe("story_posted push", () => {
  test("queues one alert per partner device and never carries the caption", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en", token: "a" });
    await addDevice(t, couple.second.userId, { locale: "nb-NO", token: "b" });
    await addDevice(t, couple.first.userId, { locale: "en", token: "c" });
    const story = await post(t, couple, { caption: "Secret caption" });
    await story.run();

    const rows = await outbox(t);
    expect(rows).toHaveLength(2);
    expect(new Set(rows.map((row) => row.recipient_user_id))).toEqual(new Set([couple.second.userId]));
    expect(rows.map((row) => row.title).sort()).toEqual(["First Partner delte en story", "First Partner shared a story"]);
    expect(rows.map((row) => row.body).sort()).toEqual(["Den ligger på Hjem i 24 timer.", "It's on Home for 24 hours."]);
    expect(rows[0].payload).toEqual({
      type: "story_posted",
      couple_id: couple.coupleId,
      story_id: story.storyId,
      actor_user_id: couple.first.userId,
      route: "home",
      deeplink: `paeonia://stories/story?storyId=${story.storyId}`,
    });
    expect(JSON.stringify(rows)).not.toContain("Secret caption");
    expect(rows[0].apns_collapse_id).toBe(`story:${couple.coupleId}`);
    expect(rows[0].dedupe_key).toContain(`story_posted:${story.storyId}`);
    expect(rows[0].kind).toBe("story_posted");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("follows the memories preference", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId)).unique();
      await ctx.db.patch(preference!._id, { memories_enabled: false });
    });
    await (await post(t, couple)).run();
    expect(await outbox(t)).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("cleanup", () => {
  test("cleanup soft-deletes the couple's stories and purge removes them, sparing other couples", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    await (await post(t, couple)).run();
    await (await post(t, couple, { user: couple.second })).run();
    const spared = await post(t, other);
    await spared.run();

    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    const afterCleanup = await storyRows(t);
    expect(afterCleanup.filter((story) => story.couple_id === couple.coupleId).map((story) => story.deleted_at)).toEqual([NOW, NOW]);
    expect(afterCleanup.find((story) => story.couple_id === other.coupleId)?.deleted_at).toBeUndefined();

    await t.run((ctx) => purgeCoupleContent(ctx, row));
    expect((await storyRows(t)).map((story) => story.id)).toEqual([spared.storyId]);
  });
});

describe("set_note", () => {
  const setNote = (user: TestUser, text: string | null, operation = op()) =>
    user.as.mutation(api.stories.set_note, { p_text: text, ...operation });

  test("both partners see each note, and a new note replaces the old one", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await setNote(couple.first, "  miss you  ")).toEqual({ user_id: couple.first.userId, text: "miss you", created_at: NOW });
    tick();
    const later = new Date(Date.now()).toISOString();
    await setNote(couple.first, "coffee later?");
    await setNote(couple.second, "on my way");

    const notes = (await getStories(couple.second)).notes;
    expect(notes).toHaveLength(2);
    expect(notes).toContainEqual({ user_id: couple.first.userId, text: "coffee later?", created_at: later });
    expect(notes).toContainEqual({ user_id: couple.second.userId, text: "on my way", created_at: later });
  });

  test("null or blank removes the note", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await setNote(couple.first, "hi");
    expect(await setNote(couple.first, "   ")).toBeNull();
    expect((await getStories(couple.first)).notes).toEqual([]);
    await setNote(couple.first, "hi again");
    expect(await setNote(couple.first, null)).toBeNull();
    expect((await getStories(couple.first)).notes).toEqual([]);
  });

  test("caps the length", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await failure(setNote(couple.first, "a".repeat(121)))).code).toBe("23514");
    expect((await setNote(couple.first, "😀".repeat(120)))?.text).toBe("😀".repeat(120));
  });

  test("a late retry does not bring back an older note", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const first = op();
    const second = op();
    await setNote(couple.first, "newer", second);
    expect(await setNote(couple.first, "older", first)).toEqual(expect.objectContaining({ text: "newer" }));
  });

  test("needs an entitled couple", async () => {
    const t = newTest();
    const single = await createSignedInUser(t, { name: "Solo" });
    expect((await failure(setNote(single, "hi"))).code).toBe("42501");
  });

  test("cleanup and purge delete the couple's notes", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    await setNote(couple.first, "hi");
    await setNote(other.first, "stays");
    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, NOW));
    const notes = await t.run((ctx) => ctx.db.query("couple_notes").collect());
    expect(notes.map((note) => note.text)).toEqual(["stays"]);
  });
});

describe("delete_expired_notes", () => {
  const setNote = (user: TestUser, text: string) => user.as.mutation(api.stories.set_note, { p_text: text, ...op() });

  test("deletes notes older than 24 hours and keeps newer notes and every story", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await setNote(couple.first, "old");
    const story = await post(t, couple);
    await story.run();
    tick(23 * 3600);
    await setNote(couple.second, "new");
    tick(3600);

    expect(await t.mutation(internal.stories.delete_expired_notes, {})).toEqual({ deleted: 1 });
    const notes = (await getStories(couple.first)).notes;
    expect(notes.map((note) => note.text)).toEqual(["new"]);
    expect((await getStories(couple.first)).stories.map((row) => row.id)).toEqual([story.storyId]);
  });

  test("a note set again restarts its 24 hours", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await setNote(couple.first, "first");
    tick(20 * 3600);
    await setNote(couple.first, "again");
    tick(5 * 3600);

    expect(await t.mutation(internal.stories.delete_expired_notes, {})).toEqual({ deleted: 0 });
    expect((await getStories(couple.first)).notes.map((note) => note.text)).toEqual(["again"]);
  });
});
