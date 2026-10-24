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

/** What a chat thread is about: a daily question, a memory (comments) or a story (replies). */
export const threadKind = literals("daily_question", "memory", "story");

export const authProvider = literals("apple", "google", "unknown");
export const apnsEnvironment = literals("sandbox", "production");
export const storekitEnvironment = literals("xcode", "sandbox", "production");
export const grantKind = literals("lifetime", "review", "test", "beta");
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
/** The iOS location access the phone last reported for Paeonia. */
export const locationPermission = literals("always", "when_in_use", "denied", "restricted", "not_determined");
export const activityKind = literals(
  "daily_answer_submitted",
  "widget_drawing_saved",
  "memory_created",
  "memory_updated",
  "thread_message_sent",
  "game_turn_completed",
  "topic_answer_submitted",
);
/**
 * What a reaction can be put on. Each kind has one access check in `lib/reactions.ts`. A new kind
 * adds its name here and its entry in `REACTION_TARGETS`.
 */
export const REACTION_TARGET_KINDS = [
  "daily_answer",
  "thread_message",
  "story",
  "memory",
  "widget_drawing",
  "draw_and_guess_round",
  "exquisite_corpse_figure",
  "story_chain_story",
] as const;
export const reactionTargetKind = literals(...REACTION_TARGET_KINDS);
export const notificationKind = literals(
  "streak_reminder",
  "daily_challenge_completed",
  "partner_answered",
  "widget_updated",
  "location_updated",
  "location_pause_ended",
  "subscription_trial_reminder",
  "subscription_payment_failed",
  "subscription_ending",
  "memory_created",
  "story_posted",
  "thread_message_sent",
  "thread_message_deleted",
  "game_turn_ready",
  "game_result",
  "game_invite",
  "game_turn_reminder",
  "question_time_reminder",
  "date_reminder",
  "partner_joined",
  "pairing_invite_reminder",
  "topics_waiting",
  "reaction_added",
  "badge_update",
  "data_export_ready",
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
  "consensio",
  "guess_my_spot",
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

/**
 * What a person can favorite. Each kind has a loader in `lib/favorites.ts`, so adding a kind means
 * adding a name here and one loader there.
 */
export const FAVORITE_KINDS = [
  "daily_question",
  "daily_answer",
  "widget_drawing",
  "game_round",
  "corpse_figure",
  "story_chain_story",
] as const;
export const favoriteKind = literals(...FAVORITE_KINDS);

/**
 * The signed-out welcome steps the app counts (`onboarding:record_welcome_step`). The counts
 * are per day and step only, so a step name is all the app sends.
 */
export const WELCOME_STEPS = [
  "welcome_shown",
  "start_chosen",
  "joiner_chosen",
  "returning_chosen",
  "date_saved",
  "date_skipped",
  "drawing_sent",
  "drawing_skipped",
  "sign_in_shown",
  "signed_in",
] as const;
export const welcomeStep = literals(...WELCOME_STEPS);
