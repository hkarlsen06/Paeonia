import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

/** The first partner posts a story, which waits for the second partner until they open it. */
async function postStory(t: TestConvex, couple: TestCouple): Promise<string> {
  const storyId = newUuid();
  const up = await uploadAsset(t, couple.first, { ...photo(couple.coupleId, "story", "story_photo"), parentId: storyId });
  await couple.first.as.mutation(api.stories.post_story, { p_story_id: storyId, p_media_asset_id: up.assetId, ...op() });
  return storyId;
}

describe("get_badges", () => {
  test("refuses a caller who is not signed in", async () => {
    const t = newTest();
    await expect(t.query(api.badges.get_badges, {})).rejects.toThrow();
  });

  test("is zero for someone without a couple", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    expect(await user.as.query(api.badges.get_badges, {})).toEqual({ questions: 0, games: 0, home: 0, icon: 0 });
  });

  test("counts the partner's unseen story for the partner only, until it is opened", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const storyId = await postStory(t, couple);
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ home: 1, icon: 1 });
    expect(await couple.first.as.query(api.badges.get_badges, {})).toMatchObject({ home: 0, icon: 0 });
    await couple.second.as.mutation(api.stories.mark_story_seen, { p_story_id: storyId });
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ home: 0, icon: 0 });
  });

  test("leaves a kind the person switched off out of the icon, but not out of its tab", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await postStory(t, couple);
    await couple.second.as.mutation(api.identity.set_notification_preference, {
      p_column: "memories_enabled",
      p_enabled: false,
    });
    expect(await couple.second.as.query(api.badges.get_badges, {})).toMatchObject({ home: 1, icon: 0 });
  });
});

describe("sync_badge", () => {
  test("refuses a caller who is not signed in", async () => {
    const t = newTest();
    await expect(t.mutation(api.badges.sync_badge, {})).rejects.toThrow();
  });

  test("queues one badge-only push per phone of the caller, and none while one is on the way", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    await addDevice(t, couple.second.userId);
    await addDevice(t, couple.first.userId);
    await couple.second.as.mutation(api.badges.sync_badge, {});
    await couple.second.as.mutation(api.badges.sync_badge, {});
    const rows = await outbox(t);
    expect(rows).toHaveLength(2);
    for (const row of rows) {
      expect(row).toMatchObject({
        kind: "badge_update",
        recipient_user_id: couple.second.userId,
        apns_push_type: "alert",
        payload: { type: "badge_update" },
      });
      expect(row.title).toBeUndefined();
      expect(row.body).toBeUndefined();
    }
  });
});
