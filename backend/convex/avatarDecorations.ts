import { mutation } from "./_generated/server";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { fail } from "./lib/errors";
import { findProfile, updateProfile } from "./lib/profiles";
import { avatarDecoration } from "./lib/validators";

export const set_own_decoration = mutation({
  args: { p_decoration: avatarDecoration },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const profile = await findProfile(ctx, userId);
    if (!profile || profile.deleted_at !== undefined) fail("42501", "active profile required");
    await updateProfile(ctx, profile, {
      avatar_decoration: args.p_decoration === "none" ? undefined : args.p_decoration,
    });
    return args.p_decoration;
  },
});
