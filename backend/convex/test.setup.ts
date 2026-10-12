/// <reference types="vite/client" />
// Shared test helpers. The two dots in the file name keep Convex from bundling this file.
import { convexTest } from "convex-test";
import { api } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { ensureCurrentUser } from "./lib/auth";
import { newUuid } from "./lib/ids";
import { nowIso } from "./lib/time";
import schema from "./schema";

export const modules = import.meta.glob(["./**/*.{ts,js}", "!./**/*.*.*"]);

export function newTest() {
  return convexTest(schema, modules);
}
export type TestConvex = ReturnType<typeof newTest>;

export type TestUser = {
  userId: string;
  subject: string;
  /** A handle that runs `run`, `mutation`, and `query` as this signed-in user. */
  as: ReturnType<TestConvex["withIdentity"]>;
};

/** The `relationship_state` part of `get_access_snapshot`, or null when the user has no current relationship. */
export async function relationshipStateOf(user: TestUser) {
  const [row] = await user.as.query(api.access.get_access_snapshot, {});
  return row.relationship_state;
}

/**
 * Signs in a user through Clerk-style identity claims and provisions them with
 * `ensureCurrentUser`, like the app does on first launch.
 */
export async function createSignedInUser(
  t: TestConvex,
  options: {
    subject?: string;
    name?: string;
    timeZone?: string;
    claims?: Record<string, string>;
  } = {},
): Promise<TestUser> {
  const subject = options.subject ?? `user_${newUuid()}`;
  const as = t.withIdentity({
    subject,
    issuer: "https://clerk.test",
    ...(options.name ? { name: options.name } : {}),
    ...options.claims,
  });
  const userId = await as.run((ctx) => ensureCurrentUser(ctx));
  if (options.timeZone) {
    await setTimeZone(t, userId, options.timeZone);
  }
  return { userId, subject, as };
}

/** Sets the onboarding time zone on a user's profile. */
export async function setTimeZone(t: TestConvex, userId: string, timeZone: string): Promise<void> {
  await t.run(async (ctx) => {
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", userId))
      .unique();
    if (!profile) throw new Error("profile missing");
    await ctx.db.patch(profile._id, { time_zone_id: timeZone, time_zone_updated_at: nowIso() });
  });
}

/** Registers an active push device for a user. */
export async function addDevice(
  t: TestConvex,
  userId: string,
  options: { timeZone?: string; locale?: string; lastSeenAt?: string; token?: string } = {},
): Promise<Doc<"user_devices">> {
  return await t.run(async (ctx) => {
    const now = nowIso();
    const token = options.token ?? `token-${newUuid()}`;
    const id = await ctx.db.insert("user_devices", {
      id: newUuid(),
      user_id: userId,
      platform: "ios",
      push_token: token.padEnd(20, "x"),
      push_token_hash: token.padEnd(64, "0").slice(0, 64),
      apns_environment: "sandbox",
      locale: options.locale,
      time_zone_id: options.timeZone,
      last_seen_at: options.lastSeenAt ?? now,
      revision: 1,
      created_at: now,
      updated_at: now,
    });
    return (await ctx.db.get(id))!;
  });
}

export type TestCouple = {
  coupleId: string;
  pairId: string;
  first: TestUser;
  second: TestUser;
};

/**
 * Creates two signed-in users who are active members of one active couple.
 * `entitled` (default true) gives the first user a lifetime grant.
 */
export async function createCouple(
  t: TestConvex,
  options: { timeZones?: [string, string]; entitled?: boolean } = {},
): Promise<TestCouple> {
  const first = await createSignedInUser(t, { name: "First Partner", timeZone: options.timeZones?.[0] });
  const second = await createSignedInUser(t, { name: "Second Partner", timeZone: options.timeZones?.[1] });
  const pairId = newUuid();
  const coupleId = newUuid();
  await t.run(async (ctx) => {
    const now = nowIso();
    const [low, high] = first.userId < second.userId ? [first.userId, second.userId] : [second.userId, first.userId];
    await ctx.db.insert("relationship_pairs", { id: pairId, user_low_id: low, user_high_id: high, created_at: now });
    await ctx.db.insert("couples", {
      id: coupleId,
      pair_id: pairId,
      status: "active",
      created_by_user_id: first.userId,
      created_at: now,
      updated_at: now,
    });
    for (const [user, role] of [
      [first, "creator"],
      [second, "partner"],
    ] as const) {
      await ctx.db.insert("couple_members", {
        couple_id: coupleId,
        user_id: user.userId,
        role,
        status: "active",
        joined_at: now,
        updated_at: now,
      });
    }
  });
  if (options.entitled !== false) {
    await grantLifetime(t, first.userId);
  }
  return { coupleId, pairId, first, second };
}

/** Creates an active lifetime entitlement grant for a user. */
export async function grantLifetime(t: TestConvex, userId: string): Promise<void> {
  await t.run(async (ctx) => {
    const now = nowIso();
    await ctx.db.insert("entitlement_grants", {
      id: newUuid(),
      user_id: userId,
      grant_kind: "lifetime",
      status: "active",
      scope: "user",
      granted_at: now,
      created_at: now,
      updated_at: now,
    });
  });
}
