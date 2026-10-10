import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { addDevice, createCouple, newTest, type TestConvex, type TestCouple } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-06-28T12:30:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

function operation(sequence: number) {
  return {
    p_client_operation_id: newUuid(),
    p_client_id: "00000000-0000-0000-0000-00000000d101",
    p_client_sequence: sequence,
    p_local_created_at: "2026-06-28T12:29:00.000Z",
  };
}

async function enableSharing(user: TestCouple["first"], coupleId: string, sequence = 1) {
  return await user.as.mutation(api.location.update_location_sharing_preference, {
    p_couple_id: coupleId.toUpperCase(),
    p_is_enabled: true,
    p_consent_version: "test-v1",
    p_source: "settings_toggle",
    ...operation(sequence),
  });
}

async function seedLocation(t: TestConvex, couple: TestCouple, capturedAt: string) {
  await t.run((ctx) =>
    ctx.db.insert("latest_partner_locations", {
      couple_id: couple.coupleId,
      user_id: couple.first.userId,
      latitude: 59.95,
      longitude: 10.75,
      accuracy_m: 12.5,
      captured_at: capturedAt,
      received_at: "2026-06-28T12:00:05.000Z",
      updated_at: "2026-06-28T12:00:05.000Z",
      source: "foreground_open",
      client_operation_id: newUuid(),
      client_id: newUuid(),
      client_sequence: 1,
    }),
  );
}

async function setup() {
  const t = newTest();
  const couple = await createCouple(t);
  await enableSharing(couple.first, couple.coupleId, 1);
  await enableSharing(couple.second, couple.coupleId, 1);
  return { t, couple };
}

const update = (overrides: Record<string, unknown> = {}) => ({
  p_latitude: 1,
  p_longitude: 2,
  p_accuracy_m: 4,
  p_captured_at: "2026-06-28T11:59:00.000Z",
  p_source: "foreground_open",
  ...overrides,
});

describe("update_latest_partner_location", () => {
  // Port of location_rpc_stale_updates_test.sql.
  test("a stale update returns the stored newer row and changes nothing", async () => {
    const { t, couple } = await setup();
    await seedLocation(t, couple, "2026-06-28T12:00:00.000Z");
    const operationArgs = operation(2);
    const rows = await couple.first.as.mutation(api.location.update_latest_partner_location, {
      p_couple_id: couple.coupleId,
      ...update(),
      ...operationArgs,
    });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ captured_at: "2026-06-28T12:00:00.000Z", latitude: 59.95, longitude: 10.75 });

    const stored = await t.run((ctx) => ctx.db.query("latest_partner_locations").collect());
    expect(stored).toHaveLength(1);
    expect(stored[0]).toMatchObject({ captured_at: "2026-06-28T12:00:00.000Z", latitude: 59.95, longitude: 10.75 });

    const op = await t.run((ctx) => ctx.db.query("client_operations").collect());
    expect(op.find((row) => row.client_operation_id === operationArgs.p_client_operation_id)?.status).toBe("succeeded");
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.filter((row) => row.kind === "location_updated")).toHaveLength(0);
  });

  test("stores a newer location, rounds it, and queues a silent partner notification", async () => {
    const { t, couple } = await setup();
    await t.run((ctx) =>
      ctx.db
        .query("notification_preferences")
        .withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId))
        .unique()
        .then((preference) => ctx.db.patch(preference!._id, { location_updates_enabled: true })),
    );
    const device = await addDevice(t, couple.second.userId);

    const rows = await couple.first.as.mutation(api.location.update_latest_partner_location, {
      p_couple_id: couple.coupleId,
      ...update({ p_latitude: 59.1234567, p_longitude: 10.7654321, p_accuracy_m: 3.456, p_captured_at: "2026-06-28T12:29:00+00:00" }),
      ...operation(2),
    });
    expect(rows[0]).toMatchObject({
      couple_id: couple.coupleId,
      user_id: couple.first.userId,
      latitude: 59.123457,
      longitude: 10.765432,
      accuracy_m: 3.46,
      captured_at: "2026-06-28T12:29:00.000Z",
      received_at: "2026-06-28T12:30:00.000Z",
    });

    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox).toHaveLength(1);
    expect(outbox[0]).toMatchObject({
      kind: "location_updated",
      recipient_user_id: couple.second.userId,
      target_device_id: device.id,
      apns_push_type: "background",
      apns_collapse_id: `location:${couple.coupleId}`,
      payload: {
        type: "location_updated",
        couple_id: couple.coupleId,
        actor_user_id: couple.first.userId,
        captured_at: "2026-06-28T12:29:00.000Z",
        route: "location",
      },
    });
    expect(JSON.stringify(outbox[0].payload)).not.toMatch(/latitude|longitude/);

    // A second, newer update overwrites the row instead of inserting another.
    await couple.first.as.mutation(api.location.update_latest_partner_location, {
      p_couple_id: couple.coupleId,
      ...update({ p_captured_at: "2026-06-28T12:29:30.000Z" }),
      ...operation(3),
    });
    const stored = await t.run((ctx) => ctx.db.query("latest_partner_locations").collect());
    expect(stored).toHaveLength(1);
    expect(stored[0].latitude).toBe(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("does not notify a partner who is not sharing", async () => {
    const { t, couple } = await setup();
    await addDevice(t, couple.second.userId);
    await couple.second.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: false,
      p_source: "settings_toggle",
      ...operation(2),
    });
    await couple.first.as.mutation(api.location.update_latest_partner_location, {
      p_couple_id: couple.coupleId,
      ...update(),
      ...operation(2),
    });
    expect(await t.run((ctx) => ctx.db.query("notification_outbox").collect())).toHaveLength(0);
  });

  test("replays the stored response for the same operation and rejects a changed request", async () => {
    const { couple } = await setup();
    const args = { p_couple_id: couple.coupleId, ...update(), ...operation(2) };
    const first = await couple.first.as.mutation(api.location.update_latest_partner_location, args);
    vi.setSystemTime(new Date("2026-06-28T12:31:00.000Z"));
    const replay = await couple.first.as.mutation(api.location.update_latest_partner_location, args);
    expect(replay).toEqual(first);
    await expect(
      couple.first.as.mutation(api.location.update_latest_partner_location, { ...args, p_latitude: 5 }),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
  });

  test("validates the request", async () => {
    const { t, couple } = await setup();
    const call = (overrides: Record<string, unknown>, user = couple.first) =>
      user.as.mutation(api.location.update_latest_partner_location, {
        p_couple_id: couple.coupleId,
        ...update(),
        ...operation(9),
        ...overrides,
      });
    await expect(call({ p_source: "background" })).rejects.toThrow(/23514.*location source is not supported/);
    await expect(call({ p_latitude: 91 })).rejects.toThrow(/23514.*location payload is out of range/);
    await expect(call({ p_longitude: -181 })).rejects.toThrow(/location payload is out of range/);
    await expect(call({ p_accuracy_m: 100001 })).rejects.toThrow(/location payload is out of range/);
    await expect(call({ p_captured_at: "2026-06-28T12:36:00.000Z" })).rejects.toThrow(/location payload is out of range/);
    await expect(call({ p_latitude: null })).rejects.toThrow(/location payload is out of range/);

    const outsider = (await createCouple(t, { entitled: true })).first;
    await expect(call({}, outsider)).rejects.toThrow(/42501.*active entitled couple access is required/);

    await couple.first.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: false,
      p_source: "settings_toggle",
      ...operation(5),
    });
    await expect(call({})).rejects.toThrow(/42501.*location sharing must be enabled before updating location/);
  });

  test("rejects a user whose account is being deleted", async () => {
    const { t, couple } = await setup();
    await t.run((ctx) =>
      ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: couple.first.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        auth_delete_attempts: 0,
        created_at: "2026-06-28T12:00:00.000Z",
        updated_at: "2026-06-28T12:00:00.000Z",
      }),
    );
    await expect(
      couple.first.as.mutation(api.location.update_latest_partner_location, {
        p_couple_id: couple.coupleId,
        ...update(),
        ...operation(9),
      }),
    ).rejects.toThrow(/42501.*account deletion is in progress/);
  });
});

describe("update_location_sharing_preference", () => {
  test("enabling stores the consent version and disabling removes the stored location", async () => {
    const { t, couple } = await setup();
    await seedLocation(t, couple, "2026-06-28T12:00:00.000Z");

    const [enabled] = await enableSharing(couple.first, couple.coupleId, 2);
    expect(enabled).toMatchObject({ is_enabled: true, disabled_at: null });
    expect(enabled.enabled_at).toBe("2026-06-28T12:30:00.000Z");

    const [disabled] = await couple.first.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: false,
      p_consent_version: null,
      p_source: "settings_toggle",
      ...operation(3),
    });
    expect(disabled).toMatchObject({ is_enabled: false, disabled_at: "2026-06-28T12:30:00.000Z" });
    expect(await t.run((ctx) => ctx.db.query("latest_partner_locations").collect())).toHaveLength(0);
    const stored = await t.run((ctx) =>
      ctx.db
        .query("location_sharing_preferences")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.coupleId).eq("user_id", couple.first.userId))
        .unique(),
    );
    expect(stored?.consent_version).toBe("test-v1");
  });

  test("validates the request", async () => {
    const { couple } = await setup();
    const call = (overrides: Record<string, unknown>) =>
      couple.first.as.mutation(api.location.update_location_sharing_preference, {
        p_couple_id: couple.coupleId,
        p_is_enabled: true,
        p_consent_version: "v1",
        p_source: "settings_toggle",
        ...operation(9),
        ...overrides,
      });
    await expect(call({ p_is_enabled: null })).rejects.toThrow(/23514.*location sharing state is required/);
    await expect(call({ p_consent_version: "  " })).rejects.toThrow(/location sharing consent version is required/);
    await expect(call({ p_consent_version: "x".repeat(81) })).rejects.toThrow(/location sharing consent version is required/);
    await expect(call({ p_source: "nope" })).rejects.toThrow(/location source is not supported/);
    await expect(call({ p_couple_id: newUuid() })).rejects.toThrow(/42501.*active entitled couple access is required/);
    await expect(call({ p_couple_id: "not-a-uuid" })).rejects.toThrow(/22P02/);
  });
});

describe("get_partner_location_visibility", () => {
  test("reports each state from disabled to visible and flags old locations as stale", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const read = (user = couple.first, args: Record<string, unknown> = {}) =>
      user.as.mutation(api.location.get_partner_location_visibility, args);

    let [row] = await read();
    expect(row).toMatchObject({
      couple_id: couple.coupleId,
      viewer_user_id: couple.first.userId,
      partner_user_id: couple.second.userId,
      visibility_state: "disabled",
      viewer_sharing_enabled: false,
      partner_sharing_enabled: false,
      partner_location_latitude: null,
    });

    await enableSharing(couple.first, couple.coupleId);
    [row] = await read(couple.first, { p_couple_id: couple.coupleId });
    expect(row).toMatchObject({ visibility_state: "not_sharing", viewer_sharing_enabled: true, partner_sharing_enabled: false });

    await enableSharing(couple.second, couple.coupleId);
    [row] = await read();
    expect(row).toMatchObject({ visibility_state: "not_sharing", partner_sharing_enabled: true });

    await t.run((ctx) =>
      ctx.db.insert("latest_partner_locations", {
        couple_id: couple.coupleId,
        user_id: couple.second.userId,
        latitude: 60.1,
        longitude: 11.2,
        accuracy_m: 8,
        captured_at: "2026-06-28T12:00:00.000Z",
        received_at: "2026-06-28T12:00:00.000Z",
        updated_at: "2026-06-28T12:00:01.000Z",
        source: "manual_refresh",
        client_operation_id: newUuid(),
        client_id: newUuid(),
        client_sequence: 1,
      }),
    );
    [row] = await read();
    expect(row).toMatchObject({
      visibility_state: "visible",
      partner_location_latitude: 60.1,
      partner_location_longitude: 11.2,
      partner_location_accuracy_m: 8,
      partner_location_captured_at: "2026-06-28T12:00:00.000Z",
      partner_location_is_stale: false,
      updated_at: "2026-06-28T12:00:01.000Z",
    });

    vi.setSystemTime(new Date("2026-06-29T12:00:01.000Z"));
    [row] = await read();
    expect(row.partner_location_is_stale).toBe(true);
  });

  test("returns relationship_ended after a break up and hides the relationship from outsiders", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const outsider = (await createCouple(t)).first;
    await expect(outsider.as.mutation(api.location.get_partner_location_visibility, { p_couple_id: couple.coupleId })).rejects.toThrow(
      /42501.*relationship was not found/,
    );
    await t.run(async (ctx) => {
      const row = await ctx.db
        .query("couples")
        .withIndex("by_uuid", (q) => q.eq("id", couple.coupleId))
        .unique();
      await ctx.db.patch(row!._id, { status: "ended", ended_at: "2026-06-28T12:00:00.000Z" });
    });
    const [row] = await couple.first.as.mutation(api.location.get_partner_location_visibility, { p_couple_id: couple.coupleId });
    expect(row).toMatchObject({
      visibility_state: "relationship_ended",
      viewer_sharing_enabled: false,
      partner_sharing_enabled: false,
      updated_at: "2026-06-28T12:30:00.000Z",
    });
  });

  test("requires a signed-in user", async () => {
    const t = newTest();
    await expect(t.mutation(api.location.get_partner_location_visibility, {})).rejects.toThrow(/42501.*authenticated user required/);
  });
});
