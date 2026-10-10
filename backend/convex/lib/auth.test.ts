import { describe, expect, test } from "vitest";
import { createSignedInUser, newTest } from "../test.setup";
import { ensureCurrentUser, getCurrentUserId, requireUserId } from "./auth";

describe("auth", () => {
  test("signed-out callers have no user id and requireUserId fails with 42501", async () => {
    const t = newTest();
    expect(await t.run((ctx) => getCurrentUserId(ctx))).toBeNull();
    await expect(t.run((ctx) => requireUserId(ctx))).rejects.toThrow(/42501.*authenticated user required/);
    await expect(t.run((ctx) => ensureCurrentUser(ctx))).rejects.toThrow(/authenticated user required/);
  });

  test("a signed-in but unprovisioned user has no user id", async () => {
    const t = newTest();
    const as = t.withIdentity({ subject: "user_unprovisioned" });
    expect(await as.run((ctx) => getCurrentUserId(ctx))).toBeNull();
  });

  test("first call creates the user, profile, and default notification preferences", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {
      subject: "user_ada",
      name: "  Ada Lovelace  ",
      claims: { auth_provider: "apple", email: "ada@example.com" },
    });
    const rows = await t.run(async (ctx) => ({
      user: await ctx.db.query("users").first(),
      profile: await ctx.db.query("profiles").first(),
      preferences: await ctx.db.query("notification_preferences").first(),
    }));
    expect(rows.user).toMatchObject({
      id: user.userId,
      clerk_user_id: "user_ada",
      auth_provider: "apple",
      email: "ada@example.com",
    });
    expect(rows.profile).toMatchObject({ user_id: user.userId, display_name: "Ada Lovelace", revision: 1 });
    expect(rows.preferences).toMatchObject({
      user_id: user.userId,
      location_updates_enabled: true,
      streak_reminders_enabled: true,
      lock_screen_detail_level: "private",
    });
    expect(await user.as.run((ctx) => requireUserId(ctx))).toBe(user.userId);
  });

  test("is idempotent", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, { subject: "user_repeat", name: "Repeat" });
    expect(await user.as.run((ctx) => ensureCurrentUser(ctx))).toBe(user.userId);
    expect(await t.run(async (ctx) => (await ctx.db.query("profiles").collect()).length)).toBe(1);
  });

  test("falls back to given and family name, and truncates to 80 characters", async () => {
    const t = newTest();
    const given = t.withIdentity({ subject: "user_given", givenName: "Grace", familyName: "Hopper" });
    await given.run((ctx) => ensureCurrentUser(ctx));
    const long = t.withIdentity({ subject: "user_long", name: "x".repeat(120) });
    await long.run((ctx) => ensureCurrentUser(ctx));
    const names = await t.run(async (ctx) => (await ctx.db.query("profiles").collect()).map((p) => p.display_name));
    expect(names).toContain("Grace Hopper");
    expect(names).toContain("x".repeat(80));
  });

  test("a changed provider name overwrites the profile name and bumps the revision", async () => {
    const t = newTest();
    const first = t.withIdentity({ subject: "user_rename", name: "Old Name" });
    const userId = await first.run((ctx) => ensureCurrentUser(ctx));
    const renamed = t.withIdentity({ subject: "user_rename", name: "New Name" });
    await renamed.run((ctx) => ensureCurrentUser(ctx));
    const profile = await t.run((ctx) =>
      ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", userId)).unique(),
    );
    expect(profile).toMatchObject({ display_name: "New Name", revision: 2 });
  });

  test("an unchanged provider name keeps a name the user edited", async () => {
    const t = newTest();
    const as = t.withIdentity({ subject: "user_edit", name: "Provider Name" });
    const userId = await as.run((ctx) => ensureCurrentUser(ctx));
    await t.run(async (ctx) => {
      const profile = await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", userId)).unique();
      await ctx.db.patch(profile!._id, { display_name: "Edited" });
    });
    await as.run((ctx) => ensureCurrentUser(ctx));
    const profile = await t.run((ctx) =>
      ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", userId)).unique(),
    );
    expect(profile?.display_name).toBe("Edited");
  });

  test("provider comes from the auth_provider claim, then the picture URL, then unknown", async () => {
    const t = newTest();
    const google = t.withIdentity({ subject: "g", pictureUrl: "https://lh3.googleusercontent.com/a/x" });
    const none = t.withIdentity({ subject: "n" });
    await google.run((ctx) => ensureCurrentUser(ctx));
    await none.run((ctx) => ensureCurrentUser(ctx));
    const providers = await t.run(async (ctx) =>
      Object.fromEntries((await ctx.db.query("users").collect()).map((u) => [u.clerk_user_id, u.auth_provider])),
    );
    expect(providers).toEqual({ g: "google", n: "unknown" });
  });
});
