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

/**
 * What a chat thread is about: a daily question, a memory (comments), a story (replies), a game
 * kind, or nothing in particular (`couple`, the one chat a couple always has).
 */
export const threadKind = literals("daily_question", "memory", "story", "game", "couple");

export const authProvider = literals("apple", "google", "unknown");
export const avatarDecoration = literals("none", "peony", "ribbon", "moon", "candy",
  "mischief", "flame", "rose", "woodland", "cosy", "silver", "halloween", "christmas", "winter",
  "paint", "jelly", "racing", "hearts", "easter", "norway", "wildflowers", "newyear", "pride");
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
export const mediaType = literals("image", "video", "voice", "drawing_payload", "report_snapshot");
export const memberStatus = literals(
  "active",
  "left",
  "ended_notice_pending",
  "ended_notice_seen",
);
export const relationshipStatus = literals("active", "ended", "deleted");
/** Why `endRelationshipForPair` ended a couple. */
export const relationshipEndReason = literals(
  "user_left",
  "blocked",
  "reported",
  "moderation_block",
  "account_banned",
  "account_deletion",
);
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
  "subscription_running",
  "admin_case_opened",
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
  "relationship_restore",
  "pairing_invite_reminder",
  "topics_waiting",
  "reaction_added",
  "badge_update",
  "data_export_ready",
  "letter_arrived",
  "letter_opened",
  "missed_call",
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
  "piccante",
  "ludo",
  "consensio",
  "guess_my_spot",
] as const;
export const gameKind = literals(...GAME_KINDS);
/** How a game Live Activity push reaches the phone (`LiveActivityDelivery` in lib/liveActivities.ts). */
export const liveActivityDelivery = literals("ring", "alert", "now", "quiet");
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
 * What one person's phone measured about a call's connection, sent once when the call ends on it
 * (`calls:report_call_quality`). Facts about the connection only: no content, no location, and no
 * device id. `path` is the last path the media took, and the loss is what this phone lost of what
 * the partner sent. Fields this phone could not measure, such as for a call that never connected,
 * are left out. The `screen_` fields come only from a phone that shared its screen (sent, captured,
 * source, encode, qp, key frames, encoder, pixel format) or received the partner's (received,
 * dropped, freezes, decode). `*_fps` are medians of 2-second samples, `*_ms` the average time per
 * frame, `screen_qp` the average quantizer, and `*_limits` the percent of the sending time in which
 * each `qualityLimitationReason` held. `encoder_*` count the lines the camera's and the screen's
 * encoders logged about resets, failed frames and dropped frames during the call.
 */
const limitShares = v.object({ cpu: v.number(), bandwidth: v.number(), other: v.number(), none: v.number() });

export const callQualityReport = v.object({
  end_reason: literals(
    "hung_up",
    "no_answer",
    "missed",
    "answered_elsewhere",
    "busy",
    "offline",
    "could_not_connect",
    "microphone_denied",
    "not_partner",
    "other",
  ),
  media_connected: v.boolean(),
  answer_to_connected_ms: v.optional(v.number()),
  path: v.optional(literals("direct", "turn")),
  reconnects: v.number(),
  reconnecting_seconds: v.number(),
  median_rtt_ms: v.optional(v.number()),
  audio_loss_percent: v.optional(v.number()),
  video_loss_percent: v.optional(v.number()),
  video_sent_seconds: v.number(),
  video_received_seconds: v.number(),
  hottest_thermal_state: literals("nominal", "fair", "serious", "critical"),
  app_build: v.string(),
  video_sent_fps: v.optional(v.number()),
  video_limits: v.optional(limitShares),
  screen_sent_seconds: v.optional(v.number()),
  screen_captured_fps: v.optional(v.number()),
  screen_sent_fps: v.optional(v.number()),
  screen_source_fps: v.optional(v.number()),
  screen_sent_width: v.optional(v.number()),
  screen_sent_height: v.optional(v.number()),
  screen_limits: v.optional(limitShares),
  screen_encode_ms: v.optional(v.number()),
  screen_qp: v.optional(v.number()),
  screen_key_frames_per_minute: v.optional(v.number()),
  screen_encoder: v.optional(v.string()),
  screen_power_efficient_encoder: v.optional(v.boolean()),
  screen_pixel_format: v.optional(v.string()),
  screen_received_seconds: v.optional(v.number()),
  screen_received_fps: v.optional(v.number()),
  screen_frames_dropped: v.optional(v.number()),
  screen_freezes: v.optional(v.number()),
  screen_decode_ms: v.optional(v.number()),
  encoder_resets: v.optional(v.number()),
  encoder_failed_frames: v.optional(v.number()),
  encoder_dropped_frames: v.optional(v.number()),
});
