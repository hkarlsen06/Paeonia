import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { coupleReactions, setReaction } from "./lib/reactions";
import { reactionTargetKind } from "./lib/validators";

/**
 * Sets the caller's emoji reaction to one thing, or takes it back with a null `p_emoji`. `p_kind`
 * says what `p_target_id` is: a story, a memory, a widget drawing revision, a finished game creation,
 * or an answer or message in a question chat. Each person has one reaction per thing, and a new
 * emoji replaces the old one. `lib/reactions.ts` has the access rule of each kind. A first reaction
 * to something the partner made sends one gentle push (see `notifyOfReaction`), except in the chat.
 */
export const set_reaction = mutation({
  args: { p_kind: reactionTargetKind, p_target_id: v.string(), p_emoji: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await setReaction(ctx, userId, args.p_kind, args.p_target_id, args.p_emoji);
    return null;
  },
});

/**
 * Every reaction of the caller's couple on stories, memories, widget drawings and game creations.
 * The app subscribes to this, keeps the result, and looks a thing up by `target_kind` and
 * `target_id`. Reactions in a question chat come with the chat's own rows instead. Fails with
 * `42501` without an entitled couple.
 * ponytail: returns every reaction. Page or window it once a couple has several thousand.
 */
export const get_reactions = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    return { couple_id: coupleId, reactions: await coupleReactions(ctx, coupleId) };
  },
});
