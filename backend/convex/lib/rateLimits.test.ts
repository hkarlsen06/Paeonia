import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "../_generated/api";
import { createCouple, createSignedInUser, grantLifetime, newTest, type TestConvex } from "../test.setup";
import { newUuid } from "./ids";
import { consumeRateLimit, rateLimiter, type RateLimitName } from "./rateLimits";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
  process.env.INVITE_CODE_PEPPER = "test-pepper-value-for-pairing-invite-hashes";
});
afterEach(() => {
  vi.useRealTimers();
  delete process.env.INVITE_CODE_PEPPER;
});

async function failure(promise: Promise<unknown>) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  return error?.data;
}

let sequence = 0;
const op = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: newUuid(),
  p_client_sequence: ++sequence,
  p_local_created_at: NOW,
});

/** Empties the user's bucket, as if they had just sent a whole burst. The clock is frozen, so the stored value is current. */
async function drain(t: TestConvex, name: RateLimitName, userId: string) {
  await t.run(async (ctx) => {
    const count = Math.floor((await rateLimiter.getValue(ctx, name, { key: userId })).value);
    if (count > 0) expect((await rateLimiter.limit(ctx, name, { key: userId, count })).ok).toBe(true);
  });
}

// The burst each limit must absorb: a phone that was offline for days and sends its backlog at once.
const CONTENT_LIMITS: { name: RateLimitName; burst: number }[] = [
  { name: "threadMessage", burst: 300 },
  { name: "mediaUpload", burst: 300 },
  { name: "memoryCreate", burst: 100 },
  { name: "pairingInviteCreate", burst: 30 },
  { name: "contentReport", burst: 10 },
];

describe("consumeRateLimit", () => {
  test.each(CONTENT_LIMITS)("$name takes a burst of $burst, then fails with 53300 until a token comes back", async ({ name, burst }) => {
    const t = newTest();
    const userId = newUuid();
    const consume = () => t.run((ctx) => consumeRateLimit(ctx, name, userId));
    await t.run(async (ctx) => {
      expect((await rateLimiter.limit(ctx, name, { key: userId, count: burst - 1 })).ok).toBe(true);
    });
    await consume();
    expect(await failure(consume())).toEqual({ code: "53300", message: `too many requests: ${name}` });
    // Another user has their own bucket.
    await t.run((ctx) => consumeRateLimit(ctx, name, newUuid()));
    const { config } = await t.run((ctx) => rateLimiter.getValue(ctx, name, { key: userId }));
    vi.setSystemTime(new Date(Date.parse(NOW) + Math.ceil(config.period / config.rate) + 1));
    await consume();
  });
});

describe("limited writes", () => {
  test("create_pairing_invite stores nothing when the bucket is empty", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    await grantLifetime(t, user.userId);
    await drain(t, "pairingInviteCreate", user.userId);
    const error = await failure(
      user.as.mutation(api.pairing.create_pairing_invite, { p_invite_code: "ABC123", ...op(), p_expires_at: null }),
    );
    expect(error).toEqual({ code: "53300", message: "too many requests: pairingInviteCreate" });
    expect(await t.run((ctx) => ctx.db.query("pairing_invites").collect())).toHaveLength(0);
  });

  test("create_pending_media_upload stores nothing when the bucket is empty", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const reserve = (operation = op()) =>
      user.as.mutation(api.media.create_pending_media_upload, {
        ...operation,
        p_reserved_parent_kind: "profile_photo",
        p_reserved_parent_id: user.userId,
        p_upload_purpose: "profile_photo",
        p_media_type: "image",
        p_file_extension: "jpg",
      });
    const stored = op();
    await reserve(stored);
    await drain(t, "mediaUpload", user.userId);
    expect(await failure(reserve())).toEqual({ code: "53300", message: "too many requests: mediaUpload" });
    expect(await t.run((ctx) => ctx.db.query("media_assets").collect())).toHaveLength(1);
    // A replay of a stored reservation costs nothing.
    const [again] = await reserve(stored);
    expect(again.bucket).toBe("profile-photos");
  });

  test("create_memory and the thread writes store nothing when the bucket is empty", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const userId = couple.first.userId;
    const memoryId = newUuid();
    await couple.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_title: "Beach weekend",
      p_memory_date: "2026-10-01",
      p_note_body: "Warm sand",
      p_media_asset_ids: null,
    });

    await drain(t, "memoryCreate", userId);
    const memoryError = await failure(
      couple.first.as.mutation(api.memories.create_memory, {
        ...op(),
        p_memory_id: newUuid(),
        p_title: "Another",
        p_memory_date: "2026-10-02",
        p_note_body: "More",
        p_media_asset_ids: null,
      }),
    );
    expect(memoryError).toEqual({ code: "53300", message: "too many requests: memoryCreate" });
    expect(await t.run((ctx) => ctx.db.query("memories").collect())).toHaveLength(1);

    await drain(t, "threadMessage", userId);
    const threadError = await failure(
      couple.first.as.mutation(api.threads.create_memory_thread_with_message, {
        ...op(),
        p_memory_id: memoryId,
        p_body: "Hello",
        p_media_asset_ids: null,
      }),
    );
    expect(threadError).toEqual({ code: "53300", message: "too many requests: threadMessage" });
    expect(await t.run((ctx) => ctx.db.query("thread_messages").collect())).toHaveLength(0);
  });
});
