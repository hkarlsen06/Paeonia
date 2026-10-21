import type { WorkId } from "@convex-dev/workpool";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { addDevice, createCouple, newTest, type TestConvex, type TestCouple } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

// Every deletion queues a Clerk delete on backgroundWorkpool, whose loop waits
// on timers. Fake them all, so finishAllScheduledFunctions can move the clock,
// and stub the network, so the queued delete never leaves the test.
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(NOW));
  process.env.CLERK_SECRET_KEY = "sk_test_clerk";
  process.env.POSTHOG_PERSONAL_API_KEY = "phx_test_posthog";
  stubNetwork();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  delete process.env.CLERK_SECRET_KEY;
  delete process.env.POSTHOG_PERSONAL_API_KEY;
  delete process.env.APPLE_SIGN_IN_TEAM_ID;
  delete process.env.APPLE_SIGN_IN_KEY_ID;
  delete process.env.APPLE_SIGN_IN_PRIVATE_KEY;
});

async function expectFail(promise: Promise<unknown>, code: string, message?: string) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  expect(error?.data?.code).toBe(code);
  if (message) expect(error?.data?.message).toContain(message);
}

/** A couple whose first member signed in with Apple, with data in every table account deletion cleans. */
async function appleCoupleWithData(t: TestConvex): Promise<TestCouple & { photoId: string; deviceId: string }> {
  const couple = await createCouple(t);
  const { first } = couple;
  const photoId = newUuid();
  const device = await addDevice(t, first.userId);
  await t.run(async (ctx) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_uuid", (q) => q.eq("id", first.userId))
      .unique();
    await ctx.db.patch(user!._id, { auth_provider: "apple", email: "deleting@test.local" });
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", first.userId))
      .unique();
    await ctx.db.insert("media_assets", {
      id: photoId,
      owner_user_id: first.userId,
      reserved_parent_kind: "profile_photo",
      reserved_parent_id: first.userId,
      reserved_by_client_operation_id: newUuid(),
      bucket: "profile-photos",
      storage_path: `${first.userId}/profile.jpg`,
      media_type: "image",
      upload_purpose: "profile_photo",
      expected_media_type: "image",
      expected_bucket: "profile-photos",
      mime_type: "image/jpeg",
      byte_size: 128,
      upload_status: "finalized",
      upload_expires_at: "2026-10-11T12:00:00.000Z",
      upload_finalized_at: NOW,
      moderation_status: "visible",
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      created_at: NOW,
      updated_at: NOW,
    });
    await ctx.db.patch(profile!._id, {
      display_name: "Delete Me",
      profile_photo_asset_id: photoId,
      time_zone_id: "Europe/Oslo",
      time_zone_updated_at: NOW,
      onboarding_completed_at: NOW,
    });
    await ctx.db.insert("widget_push_devices", {
      id: newUuid(),
      user_id: first.userId,
      widget_kind: "PaeoniaWidget",
      widget_push_token: "widget-token".padEnd(20, "x"),
      widget_push_token_hash: "w".repeat(64),
      apns_environment: "sandbox",
      last_seen_at: NOW,
      revision: 1,
      created_at: NOW,
      updated_at: NOW,
    });
    await ctx.db.insert("location_sharing_preferences", {
      couple_id: couple.coupleId,
      user_id: first.userId,
      is_enabled: true,
      enabled_at: NOW,
      consent_version: "test-v1",
      source: "settings_toggle",
      updates_while_closed: false,
      created_at: NOW,
      updated_at: NOW,
    });
    await ctx.db.insert("latest_partner_locations", {
      couple_id: couple.coupleId,
      user_id: first.userId,
      latitude: 59.91,
      longitude: 10.75,
      captured_at: NOW,
      received_at: NOW,
      updated_at: NOW,
      source: "foreground_open",
      client_operation_id: newUuid(),
      client_id: newUuid(),
      client_sequence: 1,
    });
  });
  return { ...couple, photoId, deviceId: device.id };
}

const clientOperation = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: newUuid(),
  p_client_sequence: 1,
  p_local_created_at: NOW,
});

describe("request_account_deletion", () => {
  test("removes the user's data paths, ends the relationship, and records a retryable job", async () => {
    const t = newTest();
    const couple = await appleCoupleWithData(t);
    const { first, second } = couple;

    const [start] = await first.as.mutation(api.identity.request_account_deletion, {});
    expect(start).toMatchObject({
      status: "processing",
      auth_provider: "apple",
      provider_revocation_status: "manual_required",
      auth_delete_status: "ready_for_auth_delete",
    });

    const state = await t.run(async (ctx) => {
      const byUser = (table: "user_devices" | "widget_push_devices" | "notification_preferences" | "location_sharing_preferences" | "latest_partner_locations") =>
        ctx.db.query(table).collect();
      return {
        couple: await ctx.db.query("couples").first(),
        members: await ctx.db.query("couple_members").collect(),
        events: await ctx.db.query("relationship_sync_events").collect(),
        profile: await ctx.db
          .query("profiles")
          .withIndex("by_user_id", (q) => q.eq("user_id", first.userId))
          .unique(),
        deleted: [
          ...(await byUser("user_devices")),
          ...(await byUser("widget_push_devices")),
          ...(await byUser("location_sharing_preferences")),
          ...(await byUser("latest_partner_locations")),
        ].length,
        firstPreferences: (await byUser("notification_preferences")).filter((row) => row.user_id === first.userId).length,
        photo: await ctx.db
          .query("media_assets")
          .withIndex("by_uuid", (q) => q.eq("id", couple.photoId))
          .unique(),
        job: await ctx.db.query("account_deletion_jobs").first(),
        events2: await ctx.db.query("privacy_request_events").collect(),
      };
    });
    expect(state.couple).toMatchObject({ status: "ended" });
    expect(state.couple!.delete_after! > state.couple!.ended_at!).toBe(true);
    const memberStatus = Object.fromEntries(state.members.map((member) => [member.user_id, member.status]));
    expect(memberStatus).toEqual({ [first.userId]: "left", [second.userId]: "ended_notice_pending" });
    expect(state.events.some((event) => event.user_id === second.userId && event.reason === "account_deletion")).toBe(true);
    expect(state.profile).toMatchObject({ moderation_status: "hidden", deleted_at: NOW });
    expect(state.profile!.display_name).toBeUndefined();
    expect(state.profile!.profile_photo_asset_id).toBeUndefined();
    expect(state.profile!.time_zone_id).toBeUndefined();
    expect(state.profile!.onboarding_completed_at).toBeUndefined();
    expect(state.deleted).toBe(0);
    expect(state.firstPreferences).toBe(0);
    expect(state.photo).toMatchObject({ storage_delete_status: "pending" });
    expect(state.photo!.deleted_at).toBe(NOW);
    expect(state.events2.map((event) => event.event_kind).sort()).toEqual(["account_data_removed", "deletion_requested"]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("revokes pending invites and active grants", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: true });
    // Leave the couple so the first user can hold a pending invite.
    await couple.first.as.mutation(api.relationship.leave_relationship, clientOperation());
    const inviteId = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("pairing_invites", {
        id: inviteId,
        created_by_user_id: couple.first.userId,
        status: "pending",
        expires_at: "2026-10-12T12:00:00.000Z",
        created_at: NOW,
        updated_at: NOW,
      }),
    );
    await couple.first.as.mutation(api.identity.request_account_deletion, {});
    const { invite, grants } = await t.run(async (ctx) => ({
      invite: await ctx.db.query("pairing_invites").first(),
      grants: await ctx.db.query("entitlement_grants").collect(),
    }));
    expect(invite).toMatchObject({ status: "revoked", revoked_at: NOW });
    expect(grants[0]).toMatchObject({ status: "revoked", revoked_reason: "account_deleted" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a retry returns the stored tombstone and blocks new app writes", async () => {
    const t = newTest();
    const { first } = await appleCoupleWithData(t);
    const [original] = await first.as.mutation(api.identity.request_account_deletion, {});
    const [repeat] = await first.as.mutation(api.identity.request_account_deletion, {});
    expect(repeat).toEqual(original);
    const requests = await t.run((ctx) => ctx.db.query("privacy_requests").collect());
    expect(requests).toHaveLength(1);

    await expectFail(first.as.mutation(api.relationship.leave_relationship, clientOperation()), "42501", "account deletion is in progress");
    await expectFail(
      first.as.mutation(api.identity.register_user_device, {
        p_platform: "ios",
        p_push_token: "account-deletion-recreated-push-token",
        p_apns_environment: "sandbox",
      }),
      "42501",
      "account deletion is in progress",
    );
    await expectFail(
      first.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction" }),
      "42501",
      "account deletion is in progress",
    );
    await expectFail(
      first.as.mutation(api.identity.set_notification_preference, { p_column: "messages_enabled", p_enabled: false }),
      "42501",
    );
    await expectFail(first.as.mutation(api.identity.ensure_current_user, {}), "42501", "account deletion is in progress");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an unrelated user is not affected", async () => {
    const t = newTest();
    const { first, second } = await appleCoupleWithData(t);
    await first.as.mutation(api.identity.request_account_deletion, {});
    const secondProfile = await t.run((ctx) =>
      ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", second.userId)).unique(),
    );
    expect(secondProfile?.deleted_at).toBeUndefined();
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("job state machine", () => {
  test("fail, run out of tries, operator retry, and completion", async () => {
    const t = newTest();
    const { first } = await appleCoupleWithData(t);
    const [start] = await first.as.mutation(api.identity.request_account_deletion, {});
    const jobId = start.deletion_job_id;

    expect(await t.mutation(internal.accountDeletion.mark_account_deletion_provider_result, { p_job_id: jobId, p_status: "succeeded" })).toBe(true);
    await expectFail(
      t.mutation(internal.accountDeletion.mark_account_deletion_provider_result, { p_job_id: jobId, p_status: "bogus" }),
      "23514",
    );
    expect(await t.query(internal.accountDeletion.get_auth_delete_target, { p_job_id: jobId })).toEqual({
      clerk_user_id: first.subject,
      user_id: first.userId,
    });

    // A failed try records its error and leaves the job for the next try.
    expect(
      await t.mutation(internal.accountDeletion.mark_account_deletion_auth_failed, { p_job_id: jobId, p_error_code: "auth_test_failure" }),
    ).toBe(true);
    let job = await t.run((ctx) => ctx.db.query("account_deletion_jobs").first());
    expect(job).toMatchObject({ status: "ready_for_auth_delete", last_auth_delete_error_code: "auth_test_failure" });

    // The pool reports the last failed try.
    const finished = (kind: "success" | "failed") =>
      t.mutation(internal.accountDeletion.auth_delete_finished, {
        workId: "test-work" as WorkId,
        context: { job_id: jobId },
        result: kind === "failed" ? { kind, error: "auth_test_failure" } : { kind, returnValue: null },
      });
    await finished("success");
    job = await t.run((ctx) => ctx.db.query("account_deletion_jobs").first());
    expect(job!.status).toBe("ready_for_auth_delete");
    await finished("failed");
    job = await t.run((ctx) => ctx.db.query("account_deletion_jobs").first());
    expect(job).toMatchObject({ status: "attention_required", last_auth_delete_error_code: "auth_test_failure" });

    expect(await t.mutation(internal.accountDeletion.retry_account_deletion_job, { p_job_id: jobId })).toBe(true);
    job = await t.run((ctx) => ctx.db.query("account_deletion_jobs").first());
    expect(job!.status).toBe("ready_for_auth_delete");
    expect(job!.last_auth_delete_error_code).toBeUndefined();
    expect(await t.mutation(internal.accountDeletion.retry_account_deletion_job, { p_job_id: jobId })).toBe(false);

    expect(await t.mutation(internal.accountDeletion.mark_account_deletion_completed, { p_job_id: jobId })).toBe(true);
    expect(await t.mutation(internal.accountDeletion.mark_account_deletion_completed, { p_job_id: jobId })).toBe(true);
    // A completed job has nothing left to delete and cannot fail.
    expect(await t.query(internal.accountDeletion.get_auth_delete_target, { p_job_id: jobId })).toBeNull();
    expect(
      await t.mutation(internal.accountDeletion.mark_account_deletion_auth_failed, { p_job_id: jobId, p_error_code: "x" }),
    ).toBe(false);

    // A Clerk token that outlives the deletion must not act as the deleted user.
    await expectFail(first.as.mutation(api.identity.ensure_current_user, {}), "42501", "account deletion is in progress");
    await expectFail(
      first.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: first.userId }),
      "42501",
      "not authorized",
    );
    await expectFail(first.as.query(api.identity.get_notification_preferences, {}), "42501", "authenticated user required");
    expect(await t.run((ctx) => ctx.db.query("app_account_tokens").collect())).toHaveLength(0);

    // Client operations go in a scheduled batch job.
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const done = await t.run(async (ctx) => ({
      job: await ctx.db.query("account_deletion_jobs").first(),
      request: await ctx.db.query("privacy_requests").first(),
      profile: await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", first.userId))
        .unique(),
      user: await ctx.db
        .query("users")
        .withIndex("by_uuid", (q) => q.eq("id", first.userId))
        .unique(),
      tokens: await ctx.db.query("app_account_tokens").collect(),
      operations: await ctx.db.query("client_operations").collect(),
    }));
    expect(done.job).toMatchObject({ status: "completed" });
    expect(done.job!.completed_at).toBeDefined();
    expect(done.request).toMatchObject({ status: "completed", visible_status_message: "Your Paeonia account has been deleted." });
    // The identity delete removes the tombstoned profile and the user's other cascade rows.
    expect(done.profile).toBeNull();
    expect(done.operations).toHaveLength(0);
    expect(done.tokens).toHaveLength(0);
    expect(done.user).toMatchObject({ clerk_user_id: first.subject });
    expect(done.user!.email).toBeUndefined();

    // The completed tombstone is still returned and still blocks an unexpired token.
    const [repeat] = await first.as.mutation(api.identity.request_account_deletion, {});
    expect(repeat).toMatchObject({ deletion_job_id: jobId, status: "completed", auth_delete_status: "completed" });
    await expectFail(
      first.as.mutation(api.identity.create_privacy_request, { p_id: newUuid(), p_kind: "correction" }),
      "42501",
      "authenticated user required",
    );
    const events = await t.run((ctx) => ctx.db.query("privacy_request_events").collect());
    expect(events.map((event) => event.event_kind)).toEqual(
      expect.arrayContaining(["provider_revocation_succeeded", "auth_delete_failed", "auth_user_deleted"]),
    );
    expect(events.filter((event) => event.event_kind === "auth_delete_failed").map((event) => event.metadata)).toEqual([
      { error_code: "auth_test_failure", requires_attention: false },
      { error_code: "auth_test_failure", requires_attention: true },
    ]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

// ---- delete_account action, with the Clerk and Apple HTTP calls stubbed ----

const APPLE_SUB = "001234.appleSubject";

async function applePrivateKeyPem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
}

function idToken(claims: Record<string, unknown>): string {
  const encode = (value: unknown) => btoa(JSON.stringify(value)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  return `${encode({ alg: "RS256" })}.${encode(claims)}.signature`;
}

type Call = { url: string; method: string; body: string };

const POSTHOG_BULK_DELETE = "https://eu.posthog.com/api/projects/309819/persons/bulk_delete/";

function stubNetwork(
  options: {
    clerkDelete?: number;
    appleSub?: string;
    noAppleAccount?: boolean;
    /** Clerk lists Apple and Google as verified links of the same user. */
    appleAndGoogle?: boolean;
    clerkUserStatus?: number;
    tokenStatus?: number;
    posthogStatus?: number;
    posthogDeletionErrors?: boolean;
  } = {},
) {
  const calls: Call[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      const method = init?.method ?? "GET";
      calls.push({ url, method, body: String(init?.body ?? "") });
      if (url.startsWith("https://api.clerk.com/v1/users/")) {
        expect((init?.headers as Record<string, string>).Authorization).toBe("Bearer sk_test_clerk");
        if (method === "DELETE") return new Response("{}", { status: options.clerkDelete ?? 200 });
        if (options.clerkUserStatus) return new Response("{}", { status: options.clerkUserStatus });
        if (options.appleAndGoogle) {
          return Response.json({
            external_accounts: [
              { provider: "oauth_google", provider_user_id: "g-1", verification: { status: "verified" } },
              { provider: "oauth_apple", provider_user_id: options.appleSub ?? APPLE_SUB, verification: { status: "verified" } },
            ],
          });
        }
        if (options.noAppleAccount) return Response.json({ external_accounts: [{ provider: "oauth_google", provider_user_id: "g-1", verification: { status: "verified" } }] });
        return Response.json({ external_accounts: [{ provider: "oauth_apple", provider_user_id: options.appleSub ?? APPLE_SUB }] });
      }
      if (url === "https://appleid.apple.com/auth/token") {
        if (options.tokenStatus) return Response.json({ error: "invalid_grant" }, { status: options.tokenStatus });
        return Response.json({
          id_token: idToken({ iss: "https://appleid.apple.com", aud: "no.paeonia.app", sub: APPLE_SUB, exp: 4_000_000_000 }),
          refresh_token: "apple-refresh-token",
        });
      }
      if (url === "https://appleid.apple.com/auth/revoke") return new Response("", { status: 200 });
      if (url === POSTHOG_BULK_DELETE) {
        expect((init?.headers as Record<string, string>).Authorization).toBe("Bearer phx_test_posthog");
        const deletionErrors = options.posthogDeletionErrors ? [{ person_uuid: "p-1", step: "delete_person" }] : [];
        return Response.json({ deletion_errors: deletionErrors }, { status: options.posthogStatus ?? 202 });
      }
      throw new Error(`unexpected fetch ${url}`);
    }),
  );
  return calls;
}

async function configureApple() {
  process.env.APPLE_SIGN_IN_TEAM_ID = "TEAMID1234";
  process.env.APPLE_SIGN_IN_KEY_ID = "KEYID12345";
  process.env.APPLE_SIGN_IN_PRIVATE_KEY = await applePrivateKeyPem();
}

describe("delete_account action", () => {
  test("revokes Apple, deletes the Clerk user, and completes the job", async () => {
    const t = newTest();
    await configureApple();
    const calls = stubNetwork();
    const { first } = await appleCoupleWithData(t);

    const response = await first.as.action(api.identity.delete_account, { appleAuthorizationCode: "auth-code" });
    expect(response).toMatchObject({
      authDeleteStatus: "completed",
      appleRevocation: "succeeded",
      requiresManualAppleRevocation: false,
    });
    expect(calls.map((call) => `${call.method} ${call.url}`)).toEqual([
      `GET https://api.clerk.com/v1/users/${first.subject}`,
      "POST https://appleid.apple.com/auth/token",
      "POST https://appleid.apple.com/auth/revoke",
      `DELETE https://api.clerk.com/v1/users/${first.subject}`,
      `POST ${POSTHOG_BULK_DELETE}`,
    ]);
    expect(calls[1].body).toContain("code=auth-code");
    expect(calls[2].body).toContain("token=apple-refresh-token");
    const secret = new URLSearchParams(calls[1].body).get("client_secret")!;
    expect(secret.split(".")).toHaveLength(3);
    expect(JSON.parse(atob(secret.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")))).toEqual({ alg: "ES256", kid: "KEYID12345" });

    const job = await t.run((ctx) => ctx.db.query("account_deletion_jobs").first());
    expect(job).toMatchObject({ status: "completed", provider_revocation_status: "succeeded" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("falls back to manual Apple revocation but still deletes the account", async () => {
    const t = newTest();
    const calls = stubNetwork();
    const { first } = await appleCoupleWithData(t);
    const response = await first.as.action(api.identity.delete_account, {});
    expect(response).toMatchObject({
      authDeleteStatus: "completed",
      appleRevocation: "manual_required",
      requiresManualAppleRevocation: true,
      revocationErrorCode: "authorization_code_missing",
    });
    expect(calls.filter((call) => call.method === "DELETE")).toHaveLength(1);
    expect(calls.some((call) => call.url.includes("appleid.apple.com"))).toBe(false);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("reports a mismatched Apple identity and a failed token exchange", async () => {
    await configureApple();
    for (const [options, errorCode] of [
      [{ appleSub: "someone-else" }, "apple_identity_mismatch"],
      [{ tokenStatus: 400 }, "token_invalid_grant"],
    ] as const) {
      const t = newTest();
      stubNetwork(options);
      const { first } = await appleCoupleWithData(t);
      const response = await first.as.action(api.identity.delete_account, { appleAuthorizationCode: "auth-code" });
      expect(response).toMatchObject({ requiresManualAppleRevocation: true, revocationErrorCode: errorCode });
      await t.finishAllScheduledFunctions(vi.runAllTimers);
    }
  });

  test("an Apple account linked in Clerk needs revocation even without a provider claim", async () => {
    const t = newTest();
    stubNetwork();
    const { first } = await createCouple(t);
    // createCouple users carry no auth_provider claim, so only Clerk's answer marks them as Apple.
    const response = await first.as.action(api.identity.delete_account, {});
    expect(response.appleRevocation).not.toBe("not_required");
    const job = await t.run((ctx) => ctx.db.query("account_deletion_jobs").first());
    expect(job?.auth_provider).toBe("apple");
  });

  test("rejects a signed out caller, and repeats the stored result for a second call", async () => {
    const t = newTest();
    stubNetwork();
    await expectFail(t.action(api.identity.delete_account, {}), "not_signed_in", "Invalid session");
    const { first } = await createCouple(t);
    const firstResponse = await first.as.action(api.identity.delete_account, {});
    expect(firstResponse.authDeleteStatus).toBe("completed");
    const again = await first.as.action(api.identity.delete_account, {});
    expect(again.requestId).toBe(firstResponse.requestId);
    expect(await t.run((ctx) => ctx.db.query("privacy_requests").collect())).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("an account with Apple and Google linked", () => {
  const storedProvider = (t: TestConvex, userId: string) =>
    t.run(async (ctx) => (await ctx.db.query("users").withIndex("by_uuid", (q) => q.eq("id", userId)).unique())!.auth_provider);

  test("sync_sign_in_methods refuses a caller who is signed out", async () => {
    const t = newTest();
    await expectFail(t.action(api.identity.sync_sign_in_methods, {}), "not_signed_in", "Invalid session");
  });

  test("sync_sign_in_methods stores Apple when it is linked next to Google", async () => {
    const t = newTest();
    stubNetwork({ appleAndGoogle: true });
    const { first } = await createCouple(t);
    await t.run(async (ctx) => {
      const user = await ctx.db.query("users").withIndex("by_uuid", (q) => q.eq("id", first.userId)).unique();
      await ctx.db.patch(user!._id, { auth_provider: "google" });
    });

    expect(await first.as.action(api.identity.sync_sign_in_methods, {})).toEqual({ auth_provider: "apple" });
    expect(await storedProvider(t, first.userId)).toBe("apple");

    // Unlinking Apple leaves Google.
    stubNetwork({ noAppleAccount: true });
    expect(await first.as.action(api.identity.sync_sign_in_methods, {})).toEqual({ auth_provider: "google" });
    expect(await storedProvider(t, first.userId)).toBe("google");
  });

  test("sync_sign_in_methods keeps the stored provider when Clerk cannot be asked", async () => {
    const t = newTest();
    stubNetwork({ clerkUserStatus: 500 });
    const { first } = await createCouple(t);
    await expectFail(first.as.action(api.identity.sync_sign_in_methods, {}), "sign_in_methods_unavailable");
  });

  test("delete_account revokes Apple for a user whose stored provider is Google", async () => {
    const t = newTest();
    await configureApple();
    const calls = stubNetwork({ appleAndGoogle: true });
    const { first } = await createCouple(t);
    await t.run(async (ctx) => {
      const user = await ctx.db.query("users").withIndex("by_uuid", (q) => q.eq("id", first.userId)).unique();
      await ctx.db.patch(user!._id, { auth_provider: "google" });
    });

    const response = await first.as.action(api.identity.delete_account, { appleAuthorizationCode: "auth-code" });
    expect(response).toMatchObject({ appleRevocation: "succeeded", requiresManualAppleRevocation: false });
    expect(calls.some((call) => call.url === "https://appleid.apple.com/auth/revoke")).toBe(true);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("delete_account still revokes Apple when Clerk cannot list the linked accounts but the app sent an Apple code", async () => {
    const t = newTest();
    await configureApple();
    // The earlier sync failed, so the stored provider is Google, and Clerk's lookup fails now too.
    const calls = stubNetwork({ clerkUserStatus: 500 });
    const { first } = await createCouple(t);
    await t.run(async (ctx) => {
      const user = await ctx.db.query("users").withIndex("by_uuid", (q) => q.eq("id", first.userId)).unique();
      await ctx.db.patch(user!._id, { auth_provider: "google" });
    });

    const response = await first.as.action(api.identity.delete_account, { appleAuthorizationCode: "auth-code" });
    expect(response).toMatchObject({ appleRevocation: "succeeded", requiresManualAppleRevocation: false });
    expect(calls.some((call) => call.url === "https://appleid.apple.com/auth/revoke")).toBe(true);
    expect(await t.run((ctx) => ctx.db.query("account_deletion_jobs").first())).toMatchObject({ auth_provider: "apple" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a Clerk answer of no Apple account is trusted, even when a code is sent", async () => {
    const t = newTest();
    await configureApple();
    const calls = stubNetwork({ noAppleAccount: true });
    const { first } = await createCouple(t);
    // Clerk answered: no Apple account is linked, so a code does not start a revocation.
    const response = await first.as.action(api.identity.delete_account, { appleAuthorizationCode: "auth-code" });
    expect(response).toMatchObject({ appleRevocation: "not_required" });
    expect(calls.some((call) => call.url.includes("appleid.apple.com"))).toBe(false);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a deletion stored without Apple is upgraded once Clerk shows Apple is linked", async () => {
    const t = newTest();
    await configureApple();
    const { first } = await createCouple(t);
    // The app's fallback request ran while Clerk could not be asked.
    await first.as.mutation(api.identity.request_account_deletion, {});
    expect(await t.run((ctx) => ctx.db.query("account_deletion_jobs").first())).toMatchObject({ auth_provider: "unknown" });

    const calls = stubNetwork({ appleAndGoogle: true });
    const response = await first.as.action(api.identity.delete_account, { appleAuthorizationCode: "auth-code" });
    expect(response.appleRevocation).toBe("succeeded");
    expect(calls.some((call) => call.url === "https://appleid.apple.com/auth/revoke")).toBe(true);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("queued Clerk delete", () => {
  const clerkDeletes = (calls: Call[]) => calls.filter((call) => call.method === "DELETE").length;
  const jobOf = (t: TestConvex) => t.run((ctx) => ctx.db.query("account_deletion_jobs").first());

  test("a request without the delete_account action still deletes the Clerk user", async () => {
    const t = newTest();
    const calls = stubNetwork({ noAppleAccount: true });
    const { first } = await createCouple(t);
    await first.as.mutation(api.identity.request_account_deletion, {});
    expect(await jobOf(t)).toMatchObject({ status: "ready_for_auth_delete" });

    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await jobOf(t)).toMatchObject({ status: "completed" });
    expect(clerkDeletes(calls)).toBe(1);
  });

  test("a failed Clerk delete is queued, and a later try finishes it", async () => {
    const t = newTest();
    const calls = stubNetwork({ clerkDelete: 500, noAppleAccount: true });
    const { first } = await createCouple(t);
    const response = await first.as.action(api.identity.delete_account, {});
    expect(response).toMatchObject({ authDeleteStatus: "queued", appleRevocation: "not_required", requiresManualAppleRevocation: false });
    expect(await jobOf(t)).toMatchObject({ status: "ready_for_auth_delete", last_auth_delete_error_code: "auth_http_500" });

    // Clerk answers 404 now, which counts as deleted.
    const later = stubNetwork({ clerkDelete: 404, noAppleAccount: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const job = await jobOf(t);
    expect(job).toMatchObject({ status: "completed" });
    expect(job!.last_auth_delete_error_code).toBeUndefined();
    expect(clerkDeletes(calls)).toBe(1);
    expect(clerkDeletes(later)).toBe(1);
  });

  test("a Clerk delete that fails every try needs an operator", async () => {
    const t = newTest();
    const calls = stubNetwork({ clerkDelete: 503, noAppleAccount: true });
    const { first } = await createCouple(t);
    expect((await first.as.action(api.identity.delete_account, {})).authDeleteStatus).toBe("queued");

    await t.finishAllScheduledFunctions(vi.runAllTimers, 1000);
    expect(await jobOf(t)).toMatchObject({ status: "attention_required", last_auth_delete_error_code: "auth_http_503" });
    // One try inside delete_account, then ten from the pool.
    expect(clerkDeletes(calls)).toBe(11);
    const request = await t.run((ctx) => ctx.db.query("privacy_requests").first());
    expect(request!.status).toBe("processing");
    const events = await t.run((ctx) => ctx.db.query("privacy_request_events").collect());
    expect(events.filter((event) => event.event_kind === "auth_delete_failed").at(-1)!.metadata).toEqual({
      error_code: "auth_http_503",
      requires_attention: true,
    });
  });
});

describe("PostHog delete", () => {
  const jobOf = (t: TestConvex) => t.run((ctx) => ctx.db.query("account_deletion_jobs").first());

  test("deletes the person's events and recordings with the Clerk user", async () => {
    const t = newTest();
    const calls = stubNetwork({ noAppleAccount: true });
    const { first } = await createCouple(t);

    expect((await first.as.action(api.identity.delete_account, {})).authDeleteStatus).toBe("completed");
    const posthog = calls.filter((call) => call.url === POSTHOG_BULK_DELETE);
    expect(posthog).toHaveLength(1);
    expect(posthog[0].method).toBe("POST");
    expect(JSON.parse(posthog[0].body)).toEqual({
      distinct_ids: [first.userId],
      delete_events: true,
      delete_recordings: true,
    });
    expect(await jobOf(t)).toMatchObject({ status: "completed" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a failed PostHog delete keeps the job open until a later try works", async () => {
    const t = newTest();
    stubNetwork({ noAppleAccount: true, posthogStatus: 500 });
    const { first } = await createCouple(t);

    expect((await first.as.action(api.identity.delete_account, {})).authDeleteStatus).toBe("queued");
    expect(await jobOf(t)).toMatchObject({ status: "ready_for_auth_delete", last_auth_delete_error_code: "analytics_http_500" });

    stubNetwork({ clerkDelete: 404, noAppleAccount: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await jobOf(t)).toMatchObject({ status: "completed" });
  });

  test("a deletion error inside an accepted response keeps the job open", async () => {
    const t = newTest();
    stubNetwork({ noAppleAccount: true, posthogDeletionErrors: true });
    const { first } = await createCouple(t);

    expect((await first.as.action(api.identity.delete_account, {})).authDeleteStatus).toBe("queued");
    expect(await jobOf(t)).toMatchObject({
      status: "ready_for_auth_delete",
      last_auth_delete_error_code: "analytics_deletion_failed",
    });

    stubNetwork({ clerkDelete: 404, noAppleAccount: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await jobOf(t)).toMatchObject({ status: "completed" });
  });

  test("a backend without a PostHog key keeps the job open", async () => {
    delete process.env.POSTHOG_PERSONAL_API_KEY;
    const t = newTest();
    const calls = stubNetwork({ noAppleAccount: true });
    const { first } = await createCouple(t);

    expect((await first.as.action(api.identity.delete_account, {})).authDeleteStatus).toBe("queued");
    expect(calls.some((call) => call.url === POSTHOG_BULK_DELETE)).toBe(false);
    expect(await jobOf(t)).toMatchObject({
      status: "ready_for_auth_delete",
      last_auth_delete_error_code: "analytics_configuration_missing",
    });
  });
});
