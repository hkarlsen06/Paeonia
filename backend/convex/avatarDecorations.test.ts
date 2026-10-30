import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import { createCouple, createSignedInUser, newTest, relationshipStateOf } from "./test.setup";

describe("avatar decorations", () => {
  test.each(["peony", "ribbon", "moon", "candy",
    "mischief", "flame", "rose", "woodland", "cosy", "silver", "halloween", "christmas", "winter",
    "rope", "paint", "jelly", "racing", "hearts", "easter", "norway", "wildflowers", "newyear", "pride"] as const)("shares the caller's %s frame with their partner", async (decoration) => {
    const t = newTest();
    const { first, second } = await createCouple(t);
    await first.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: decoration });
    await second.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "moon" });
    expect(await relationshipStateOf(first)).toMatchObject({
      own_avatar_decoration: decoration, partner_avatar_decoration: "moon",
    });
    expect(await relationshipStateOf(second)).toMatchObject({
      own_avatar_decoration: "moon", partner_avatar_decoration: decoration,
    });
    await first.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "none" });
    expect(await relationshipStateOf(second)).toMatchObject({
      own_avatar_decoration: "moon", partner_avatar_decoration: null,
    });
  });

  test("refuses signed-out writes and keeps other couples' choices private", async () => {
    const t = newTest();
    const { first, second } = await createCouple(t);
    await first.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "candy" });
    await expect(t.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "moon" }))
      .rejects.toThrow(/42501/);
    await expect(t.query(api.access.get_access_snapshot, {})).rejects.toThrow(/42501/);
    const outsider = await createSignedInUser(t);
    await outsider.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "moon" });
    expect(await relationshipStateOf(outsider)).toBeNull();
    expect(await relationshipStateOf(second)).toMatchObject({ partner_avatar_decoration: "candy" });
    const otherCouple = await createCouple(t);
    expect(await relationshipStateOf(otherCouple.first)).toMatchObject({ partner_avatar_decoration: null });
  });

  test("hides a former partner's decoration after leaving", async () => {
    const t = newTest();
    const { first, second, pairId } = await createCouple(t);
    await first.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "candy" });
    await t.mutation(internal.relationshipJobs.end_relationship_for_pair, {
      pair_id: pairId, initiated_by_user_id: second.userId, reason: "user_left",
    });
    expect(await relationshipStateOf(second)).toMatchObject({ partner_avatar_decoration: null });
  });

  test("refuses banned accounts", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    await t.run(async (ctx) => {
      const row = await ctx.db.query("users").withIndex("by_uuid", (q) => q.eq("id", user.userId)).unique();
      if (!row) throw new Error("test user missing");
      await ctx.db.patch(row._id, { banned_at: new Date().toISOString() });
    });
    await expect(user.as.mutation(api.avatarDecorations.set_own_decoration, { p_decoration: "moon" }))
      .rejects.toThrow(/42501/);
  });
});
