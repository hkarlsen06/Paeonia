import { v, type VLiteral, type VUnion } from "convex/values";

/** `v.union(v.literal(...))` with the literal types preserved. */
export function literals<const T extends readonly [string, string, ...string[]]>(
  ...values: T
): VUnion<T[number], VLiteral<T[number], "required">[], "required"> {
  return v.union(...values.map((value) => v.literal(value))) as never;
}

export const moderationStatus = literals(
  "pending_review",
  "visible",
  "hidden",
  "removed",
  "rejected",
);

export const authProvider = literals("apple", "google", "unknown");
export const apnsEnvironment = literals("sandbox", "production");
export const storekitEnvironment = literals("xcode", "sandbox", "production");
export const mediaBucket = literals(
  "profile-photos",
  "couple-media",
  "widget-drawings",
  "game-drawings",
  "report-snapshots",
);
export const mediaType = literals("image", "voice", "drawing_payload", "report_snapshot");
export const memberStatus = literals(
  "active",
  "left",
  "ended_notice_pending",
  "ended_notice_seen",
);
export const relationshipStatus = literals("active", "ended", "deleted");
export const locationSource = literals("foreground_open", "manual_refresh", "settings_toggle", "background");
export const activityKind = literals(
  "daily_challenge_completed",
  "widget_drawing_saved",
  "memory_created",
  "memory_updated",
  "thread_message_sent",
  "game_turn_completed",
);
export const notificationKind = literals(
  "streak_reminder",
  "daily_challenge_completed",
  "partner_answered",
  "widget_updated",
  "location_updated",
  "subscription_trial_reminder",
  "memory_created",
  "story_posted",
  "thread_message_sent",
  "game_turn_ready",
  "game_result",
  "game_invite",
  "game_turn_reminder",
  "question_time_reminder",
  "partner_joined",
);
/** Every game, in catalog order. A new game adds its kind here and an entry in `GAME_BACKENDS` (lib/gameRegistry.ts). */
export const GAME_KINDS = [
  "draw_and_guess",
  "mind_meld",
  "exquisite_corpse",
  "story_chain",
  "connect_four",
  "dots_and_boxes",
  "ultimate_tic_tac_toe",
  "ludo",
] as const;
export const gameKind = literals(...GAME_KINDS);
export const gamePlayStyle = literals("together", "against");
export const gameLanguage = literals("en", "nb");
export const wordDifficulty = literals("easy", "medium", "hard");
export const reviewScenario = literals(
  "pre_paired_entitled",
  "purchase_flow_unentitled",
  "pre_paired_paywalled",
);
