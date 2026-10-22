import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { sha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { addDevice, createCouple, createSignedInUser, newTest, relationshipStateOf, type TestConvex } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

async function expectFail(promise: Promise<unknown>, code: string, message?: string) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  expect(error?.data?.code).toBe(code);
  if (message) expect(error?.data?.message).toContain(message);
}

async function addProfilePhoto(t: TestConvex, ownerId: string, name: string, overrides: Record<string, unknown> = {}) {
  const id = newUuid();
  const sha256 = await sha256Hex(name);
  await t.run((ctx) =>
    ctx.db.insert("media_assets", {
      id,
      owner_user_id: ownerId,
      reserved_parent_kind: "profile_photo",
      reserved_parent_id: ownerId,
      reserved_by_client_operation_id: newUuid(),
      bucket: "profile-photos",
      storage_path: `${ownerId}/${name}.jpg`,
      media_type: "image",
      upload_purpose: "profile_photo",
      expected_media_type: "image",
      expected_bucket: "profile-photos",
      mime_type: "image/jpeg",
      byte_size: 100,
      sha256,
      upload_status: "finalized",
      upload_expires_at: "2026-10-11T12:00:00.000Z",
      upload_finalized_at: "2026-10-10T12:00:00.000Z",
      moderation_status: "visible",
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      created_at: "2026-10-10T12:00:00.000Z",
      updated_at: "2026-10-10T12:00:00.000Z",
      ...overrides,
    } as never),
  );
  return id;
}

describe("profile", () => {
  test("ensure_current_user provisions the profile and notification preferences once", async () => {
    const t = newTest();
    const as = t.withIdentity({ subject: "user_new", issuer: "https://clerk.test", name: "Ada" });
    const first = await as.mutation(api.identity.ensure_current_user, {});
    expect(first).toMatchObject({ display_name: "Ada", revision: 1, moderation_status: "visible", deleted_at: null });
    const second = await as.mutation(api.identity.ensure_current_user, {});
    expect(second?.user_id).toBe(first?.user_id);
    const preferences = await as.query(api.identity.get_notification_preferences, {});
    expect(preferences).toMatchObject({ streak_reminders_enabled: true, location_updates_enabled: true });
  });

  test("signed out callers are rejected", async () => {
    const t = newTest();
    await expectFail(t.query(api.identity.get_notification_preferences, {}), "42501", "authenticated user required");
    await expectFail(t.mutation(api.identity.ensure_current_user, {}), "42501");
    await expectFail(
      t.mutation(api.identity.register_user_device, {
        p_platform: "ios",
        p_push_token: "x".repeat(30),
        p_apns_environment: "sandbox",
      }),
      "42501",
    );
  });

  test("launch provisions the user and returns the profile with the access snapshot", async () => {
    const t = newTest();
    const as = t.withIdentity({ subject: "user_new", issuer: "https://clerk.test", name: "Ada" });
    const first = await as.mutation(api.identity.launch, {});
    expect(first.profile).toMatchObject({ display_name: "Ada", revision: 1 });
    expect(first.access).toEqual({
      account_status: "active",
      user_entitlement: expect.objectContaining({ is_entitled: false }),
      couple_entitlement: null,
      relationship_state: null,
    });
    expect((await as.mutation(api.identity.launch, {})).profile?.user_id).toBe(first.profile?.user_id);

    const couple = await createCouple(t);
    const paired = await couple.second.as.mutation(api.identity.launch, {});
    expect(paired.access.account_status).toBe("active");
    expect(paired.access.relationship_state).toMatchObject({ relationship_status: "active", member_status: "active" });
    expect(paired.access.couple_entitlement).toMatchObject({ is_entitled: true });
    expect(paired.access).toEqual((await couple.second.as.query(api.access.get_access_snapshot, {}))[0]);
  });

  test("launch refuses a signed out caller and gives a banned account only the closed-account row", async () => {
    const t = newTest();
    await expectFail(t.mutation(api.identity.launch, {}), "42501", "authenticated user required");

    const user = await createSignedInUser(t, { name: "Ada" });
    await t.run(async (ctx) => {
      const row = await ctx.db
        .query("users")
        .withIndex("by_clerk_user_id", (q) => q.eq("clerk_user_id", user.subject))
        .unique();
      await ctx.db.patch(row!._id, { banned_at: "2026-10-10T12:00:00.000Z" });
    });
    const banned = await user.as.mutation(api.identity.launch, {});
    expect(banned.access).toEqual({
      account_status: "banned",
      user_entitlement: null,
      couple_entitlement: null,
      relationship_state: null,
    });
  });

  test("complete_profile_onboarding stores the time zone and finishes onboarding", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, { name: "Ada" });
    const photo = await addProfilePhoto(t, user.userId, "custom");
    const profile = await user.as.mutation(api.identity.complete_profile_onboarding, {
      p_time_zone_id: "Europe/Oslo",
      p_profile_photo_asset_id: photo,
    });
    expect(profile).toMatchObject({
      profile_photo_asset_id: photo,
      time_zone_id: "Europe/Oslo",
      time_zone_updated_at: "2026-10-10T12:00:00.000Z",
      onboarding_completed_at: "2026-10-10T12:00:00.000Z",
      revision: 2,
    });
    await expectFail(
      user.as.mutation(api.identity.complete_profile_onboarding, { p_time_zone_id: "  ", p_profile_photo_asset_id: photo }),
      "23514",
    );
    await expectFail(
      user.as.mutation(api.identity.complete_profile_onboarding, {
        p_time_zone_id: "Europe/Oslo",
        p_profile_photo_asset_id: newUuid(),
      }),
      "23503",
      "profile photo asset was not found",
    );
  });

  test("complete_profile_onboarding needs a photo but accepts the imported Google photo", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, { name: "Ada" });
    await expectFail(
      user.as.mutation(api.identity.complete_profile_onboarding, { p_time_zone_id: "Europe/Oslo" }),
      "23514",
      "a profile photo is required",
    );

    const provider = await addProfilePhoto(t, user.userId, "provider");
    await user.as.mutation(api.identity.set_own_provider_profile_photo, {
      p_profile_photo_asset_id: provider,
      p_source: "google",
    });
    const profile = await user.as.mutation(api.identity.complete_profile_onboarding, { p_time_zone_id: "Europe/Oslo" });
    expect(profile).toMatchObject({
      profile_photo_asset_id: null,
      provider_profile_photo_asset_id: provider,
      onboarding_completed_at: "2026-10-10T12:00:00.000Z",
    });
  });

  test("update_own_profile validates the name and clears the custom photo", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, { name: "Ada" });
    const custom = await addProfilePhoto(t, user.userId, "custom");
    const provider = await addProfilePhoto(t, user.userId, "provider");

    await expectFail(
      user.as.mutation(api.identity.update_own_profile, { p_display_name: "Anne Marie Hansen", p_profile_photo_asset_id: null }),
      "23514",
      "display name must be one or two names",
    );
    const doubleName = await user.as.mutation(api.identity.update_own_profile, {
      p_display_name: "  Anne   Marie ",
      p_profile_photo_asset_id: null,
    });
    expect(doubleName[0]).toMatchObject({ display_name: "Anne Marie" });
    await expectFail(
      user.as.mutation(api.identity.update_own_profile, { p_display_name: "  ", p_profile_photo_asset_id: null }),
      "23514",
    );

    const linked = await user.as.mutation(api.identity.set_own_provider_profile_photo, {
      p_profile_photo_asset_id: provider,
      p_source: "google",
    });
    expect(linked[0]).toMatchObject({ provider_profile_photo_asset_id: provider, provider_profile_photo_source: "google" });
    const withCustom = await user.as.mutation(api.identity.update_own_profile, {
      p_display_name: " Grace ",
      p_profile_photo_asset_id: custom,
    });
    expect(withCustom[0]).toMatchObject({ display_name: "Grace", profile_photo_asset_id: custom });
    expect(Object.keys(withCustom[0]).sort()).toEqual(
      [
        "display_name",
        "onboarding_completed_at",
        "profile_photo_asset_id",
        "provider_profile_photo_asset_id",
        "provider_profile_photo_source",
        "time_zone_id",
        "time_zone_updated_at",
        "user_id",
      ].sort(),
    );

    const removed = await user.as.mutation(api.identity.update_own_profile, {
      p_display_name: "Renamed",
      p_profile_photo_asset_id: null,
    });
    expect(removed[0]).toMatchObject({
      display_name: "Renamed",
      profile_photo_asset_id: null,
      provider_profile_photo_asset_id: provider,
    });
    const assets = await t.run((ctx) => ctx.db.query("media_assets").collect());
    const status = Object.fromEntries(assets.map((asset) => [asset.id, asset.storage_delete_status]));
    expect(status[custom]).toBe("pending");
    expect(status[provider]).toBe("none");
  });

  test("provider photo import rejects other people's assets and bad input", async () => {
    const t = newTest();
    const owner = await createSignedInUser(t, { name: "Owner" });
    const other = await createSignedInUser(t, { name: "Other" });
    const foreign = await addProfilePhoto(t, other.userId, "foreign");
    await expectFail(
      owner.as.mutation(api.identity.set_own_provider_profile_photo, { p_profile_photo_asset_id: foreign, p_source: "google" }),
      "23514",
      "profile photo asset is not usable",
    );
    const own = await addProfilePhoto(t, owner.userId, "own");
    await expectFail(
      owner.as.mutation(api.identity.set_own_provider_profile_photo, { p_profile_photo_asset_id: own, p_source: "apple" }),
      "23514",
      "provider profile photo input is invalid",
    );
    await expectFail(
      owner.as.mutation(api.identity.set_own_provider_profile_photo, { p_profile_photo_asset_id: null, p_source: "google" }),
      "23514",
    );
    const pending = await addProfilePhoto(t, owner.userId, "pending", { storage_delete_status: "pending" });
    await expectFail(
      owner.as.mutation(api.identity.update_own_profile, { p_display_name: "Owner", p_profile_photo_asset_id: pending }),
      "23514",
      "not usable",
    );
  });

  test("the partner sees the custom photo first and the provider fallback after it is removed", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { first, second } = couple;
    const custom = await addProfilePhoto(t, first.userId, "custom");
    const provider = await addProfilePhoto(t, first.userId, "provider");
    await first.as.mutation(api.identity.set_own_provider_profile_photo, { p_profile_photo_asset_id: provider, p_source: "google" });
    await first.as.mutation(api.identity.update_own_profile, { p_display_name: "First", p_profile_photo_asset_id: custom });
    const before = await relationshipStateOf(second);
    expect(before!.partner_profile_photo_asset_id).toBe(custom);
    await first.as.mutation(api.identity.update_own_profile, { p_display_name: "First", p_profile_photo_asset_id: null });
    const after = await relationshipStateOf(second);
    expect(after!.partner_profile_photo_asset_id).toBe(provider);
    expect(after!.partner_account_name).toBe("First");
  });

  test("a paired user can change their time zone during onboarding", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const photo = await addProfilePhoto(t, couple.first.userId, "custom");
    const profile = await couple.first.as.mutation(api.identity.complete_profile_onboarding, {
      p_time_zone_id: "Asia/Tokyo",
      p_profile_photo_asset_id: photo,
    });
    expect(profile?.time_zone_id).toBe("Asia/Tokyo");
  });
});

describe("devices", () => {
  const token = (suffix: string) => `push-token-${suffix}`.padEnd(40, "0");

  test("register_user_device validates input and trims optional text", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const base = { p_platform: "ios", p_push_token: token("a"), p_apns_environment: "sandbox" };
    await expectFail(user.as.mutation(api.identity.register_user_device, { ...base, p_platform: "android" }), "23514", "unsupported device platform");
    await expectFail(user.as.mutation(api.identity.register_user_device, { ...base, p_push_token: "short" }), "23514", "invalid push token");
    await expectFail(user.as.mutation(api.identity.register_user_device, { ...base, p_apns_environment: "dev" }), "23514", "unsupported APNs environment");
    await expectFail(user.as.mutation(api.identity.register_user_device, { ...base, p_locale: "x" }), "23514");

    const id = await user.as.mutation(api.identity.register_user_device, {
      ...base,
      p_locale: " nb-NO ",
      p_time_zone_id: " ",
      p_app_version: "1.0",
    });
    const device = await t.run((ctx) => ctx.db.query("user_devices").first());
    expect(device).toMatchObject({
      id,
      user_id: user.userId,
      locale: "nb-NO",
      app_version: "1.0",
      push_token_hash: await sha256Hex(token("a")),
      revision: 1,
    });
    expect(device?.time_zone_id).toBeUndefined();
  });

  test("registering the same token again updates the device, and a disabled device gets a new row", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const args = { p_platform: "ios", p_push_token: token("a"), p_apns_environment: "sandbox" };
    const id = await user.as.mutation(api.identity.register_user_device, args);
    vi.setSystemTime(new Date("2026-10-10T12:05:00.000Z"));
    expect(await user.as.mutation(api.identity.register_user_device, { ...args, p_locale: "en-US" })).toBe(id);
    let devices = await t.run((ctx) => ctx.db.query("user_devices").collect());
    expect(devices).toHaveLength(1);
    expect(devices[0]).toMatchObject({ locale: "en-US", revision: 2, last_seen_at: "2026-10-10T12:05:00.000Z" });

    expect(await user.as.mutation(api.identity.disable_user_device, { p_device_id: id })).toBe(true);
    const replacement = await user.as.mutation(api.identity.register_user_device, args);
    expect(replacement).not.toBe(id);
    devices = await t.run((ctx) => ctx.db.query("user_devices").collect());
    expect(devices).toHaveLength(2);
  });

  test("a token moves to the newest account and the old account's device is disabled", async () => {
    const t = newTest();
    const first = await createSignedInUser(t, {});
    const second = await createSignedInUser(t, {});
    const args = { p_platform: "ios", p_push_token: token("shared"), p_apns_environment: "sandbox" };
    const firstId = await first.as.mutation(api.identity.register_user_device, args);
    const secondId = await second.as.mutation(api.identity.register_user_device, args);
    expect(secondId).not.toBe(firstId);
    const devices = await t.run((ctx) => ctx.db.query("user_devices").collect());
    const byId = Object.fromEntries(devices.map((device) => [device.id, device]));
    expect(byId[firstId].disabled_at).toBe("2026-10-10T12:00:00.000Z");
    expect(byId[secondId].disabled_at).toBeUndefined();
  });

  test("disable_user_device only touches the caller's own devices", async () => {
    const t = newTest();
    const owner = await createSignedInUser(t, {});
    const other = await createSignedInUser(t, {});
    const device = await addDevice(t, owner.userId);
    expect(await other.as.mutation(api.identity.disable_user_device, { p_device_id: device.id })).toBe(false);
    expect(await owner.as.mutation(api.identity.disable_user_device, { p_device_id: newUuid() })).toBe(false);
    expect(await owner.as.mutation(api.identity.disable_user_device, { p_device_id: device.id.toUpperCase() })).toBe(true);
    const row = await t.run((ctx) => ctx.db.query("user_devices").first());
    expect(row?.disabled_at).toBe("2026-10-10T12:00:00.000Z");
  });
});

describe("notification preferences", () => {
  test("set_notification_preference changes one column and bumps the revision", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const row = await user.as.mutation(api.identity.set_notification_preference, { p_column: "messages_enabled", p_enabled: false });
    expect(row).toMatchObject({ messages_enabled: false, streak_reminders_enabled: true, revision: 2 });
    expect(await user.as.query(api.identity.get_notification_preferences, {})).toMatchObject({ messages_enabled: false });
  });

  test("only the six user-facing toggles can be changed", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    await expectFail(
      user.as.mutation(api.identity.set_notification_preference, { p_column: "revision", p_enabled: true }),
      "23514",
    );
    await expectFail(
      user.as.mutation(api.identity.set_notification_preference, { p_column: "location_updates_enabled", p_enabled: true }),
      "23514",
    );
  });

  test("each user only sees and changes their own row", async () => {
    const t = newTest();
    const first = await createSignedInUser(t, {});
    const second = await createSignedInUser(t, {});
    await first.as.mutation(api.identity.set_notification_preference, { p_column: "memories_enabled", p_enabled: false });
    expect(await second.as.query(api.identity.get_notification_preferences, {})).toMatchObject({ memories_enabled: true });
  });
});

describe("lock screen detail level", () => {
  test("set_lock_screen_detail_level changes only the caller's row, and the default stays private", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const other = await createSignedInUser(t, {});
    expect(await user.as.query(api.identity.get_notification_preferences, {})).toMatchObject({
      lock_screen_detail_level: "private",
    });
    const row = await user.as.mutation(api.identity.set_lock_screen_detail_level, { p_level: "descriptive" });
    expect(row).toMatchObject({ lock_screen_detail_level: "descriptive", revision: 2 });
    expect(await other.as.query(api.identity.get_notification_preferences, {})).toMatchObject({
      lock_screen_detail_level: "private",
    });
  });

  test("a caller who is not signed in is refused", async () => {
    const t = newTest();
    await createSignedInUser(t, {});
    await expect(t.mutation(api.identity.set_lock_screen_detail_level, { p_level: "descriptive" })).rejects.toThrow();
  });
});

describe("privacy requests", () => {
  test("creates a request and lists the caller's newest first", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const other = await createSignedInUser(t, {});
    const firstId = newUuid();
    const created = await user.as.mutation(api.identity.create_privacy_request, {
      p_id: firstId.toUpperCase(),
      p_kind: "correction",
      p_requester_note: "please",
    });
    expect(created).toMatchObject({
      id: firstId,
      user_id: user.userId,
      request_kind: "correction",
      status: "submitted",
      requester_note: "please",
      verified_at: null,
      revision: 1,
    });
    vi.setSystemTime(new Date("2026-10-10T12:01:00.000Z"));
    const secondId = newUuid();
    await user.as.mutation(api.identity.create_privacy_request, { p_id: secondId, p_kind: "deletion" });
    await other.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction" });
    const listed = await user.as.query(api.identity.get_privacy_requests, {});
    expect(listed.map((row) => row.id)).toEqual([secondId, firstId]);
  });

  test("a second open request of the same kind returns the open one", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    const first = await user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction" });
    // Another device files the same request before it sees the first one.
    expect(await user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction" })).toEqual(first);
    const deletion = await user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "deletion" });
    expect(deletion.id).not.toBe(first.id);
    await t.run(async (ctx) => {
      const row = await ctx.db.query("privacy_requests").withIndex("by_uuid", (q) => q.eq("id", first.id)).unique();
      await ctx.db.patch(row!._id, { status: "completed" });
    });
    const next = await user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction" });
    expect(next.id).not.toBe(first.id);
    expect(await user.as.query(api.identity.get_privacy_requests, {})).toHaveLength(3);
  });

  test("rejects bad input, duplicate ids, and a second open deletion request", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    await expectFail(user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "sell" }), "23514");
    // Access and export are answered by "Download my data", not by a request.
    await expectFail(user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "export" }), "23514");
    await expectFail(user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "access" }), "23514");
    await expectFail(
      user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction", p_requester_note: "x".repeat(4001) }),
      "23514",
    );
    await expectFail(user.as.mutation(api.identity.create_privacy_request, { p_id: "nope", p_kind: "correction" }), "22P02");
    const id = newUuid();
    await user.as.mutation(api.identity.create_privacy_request, { p_id: id, p_kind: "correction" });
    await expectFail(user.as.mutation(api.identity.create_privacy_request, { p_id: id, p_kind: "correction" }), "23505");
    await user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "deletion" });
    await expectFail(
      user.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "deletion" }),
      "23505",
      "privacy_requests_active_deletion_user_idx",
    );
  });
});
