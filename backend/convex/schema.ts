import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  activityKind,
  apnsEnvironment,
  authProvider,
  gameKind,
  gameLanguage,
  gamePlayStyle,
  literals,
  mediaBucket,
  mediaType,
  memberStatus,
  moderationStatus,
  notificationKind,
  reactionTargetKind,
  relationshipStatus,
  reviewScenario,
  storekitEnvironment,
  threadKind,
  locationPermission,
  locationSource,
  wordDifficulty,
} from "./lib/validators";
import { LUDO_COLORS } from "./lib/ludo";
import { consensioTables } from "./lib/consensio";
import { guessMySpotTables } from "./lib/guessMySpot";
import { mindMeldTables } from "./lib/mindMeld";

// Conventions (see backend/AGENTS.md):
// - Field names match the SQL columns. uuid columns are lowercase strings.
// - Timestamps are ISO-8601 UTC strings, dates are YYYY-MM-DD, bytea is lowercase hex.
// - Nullable SQL columns are v.optional(...) and are omitted when null.
// - Partial SQL indexes are full indexes here. Callers filter the rest in code.
// - "FK" comments list the SQL delete behavior. Convex does not enforce it.
const uuid = v.string();
const ts = v.string();
const date = v.string();
const optUuid = v.optional(uuid);
const optTs = v.optional(ts);
const optString = v.optional(v.string());

const moderation = {
  moderation_status: moderationStatus,
  moderated_at: optTs,
  moderated_by: optUuid,
  moderation_report_id: optUuid,
};

export default defineSchema({
  // Maps the Clerk subject to the Paeonia user id. Replaces auth.users.
  users: defineTable({
    id: uuid,
    clerk_user_id: v.string(),
    auth_provider: authProvider,
    email: optString,
    created_at: ts,
    // Last display name seen in the Clerk claims, used to detect provider name changes.
    claim_display_name: optString,
    // Set while the account is banned. Every session lookup treats a banned user as
    // signed out, and the access snapshot reports `account_status: "banned"`.
    banned_at: optTs,
    // Why, for the admin. The banned person never sees it.
    ban_reason: optString,
    // The admin who banned, or missing for an operator command.
    banned_by_user_id: optUuid,
  })
    .index("by_uuid", ["id"])
    .index("by_clerk_user_id", ["clerk_user_id"])
    .index("by_banned_at", ["banned_at"]),

  // ---- internal schema ----

  // What admins and operator commands did, newest first in the admin screen.
  // FK: admin_user_id, target_user_id -> users (kept after a user is deleted).
  admin_audit_log: defineTable({
    id: uuid,
    action: literals("user_banned", "user_unbanned"),
    // Missing for an operator command run with `npx convex run`.
    admin_user_id: optUuid,
    operator_identifier: optString,
    target_user_id: uuid,
    reason: optString,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_created_at", ["created_at"])
    .index("by_target_user_id_created_at", ["target_user_id", "created_at"]),

  // FK: request_id -> privacy_requests restrict
  account_deletion_jobs: defineTable({
    id: uuid,
    request_id: uuid,
    user_id: uuid,
    auth_provider: authProvider,
    status: literals("ready_for_auth_delete", "attention_required", "completed"),
    provider_revocation_status: literals("not_required", "succeeded", "manual_required"),
    provider_revocation_attempted_at: optTs,
    provider_revocation_error_code: optString,
    last_auth_delete_error_code: optString,
    completed_at: optTs,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_request_id", ["request_id"])
    .index("by_user_id", ["user_id"]),

  // FK: user_id -> users cascade
  app_account_tokens: defineTable({
    user_id: uuid,
    token: uuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_user_id", ["user_id"])
    .index("by_token", ["token"]),

  // FK: user_id -> users cascade
  client_operations: defineTable({
    id: uuid,
    user_id: uuid,
    client_operation_id: uuid,
    client_id: uuid,
    client_sequence: v.number(),
    local_created_at: ts,
    operation_kind: v.string(),
    idempotency_scope: v.string(),
    request_hash: v.string(),
    response_hash: optString,
    // Any JSON value, including null. Present once status is succeeded.
    stored_response: v.optional(v.any()),
    status: literals("started", "succeeded", "failed_retryable", "failed_terminal"),
    locked_until: optTs,
    attempt_count: v.number(),
    last_attempt_at: ts,
    completed_at: optTs,
    failed_at: optTs,
    failure_code: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_user_id_client_operation_id", ["user_id", "client_operation_id"])
    .index("by_status_created_at", ["status", "created_at"])
    .index("by_user_id_created_at", ["user_id", "created_at"])
    .index("by_user_id_idempotency_scope_created_at", ["user_id", "idempotency_scope", "created_at"]),

  // FK: product_id -> subscription_products restrict; source_review_session_id -> review_access_sessions set null
  entitlement_grants: defineTable({
    id: uuid,
    user_id: uuid,
    product_id: optUuid,
    grant_kind: literals("lifetime", "review", "test", "beta"),
    status: literals("active", "expired", "revoked"),
    scope: literals("user", "review"),
    environment: v.optional(storekitEnvironment),
    source_review_session_id: optUuid,
    reason: optString,
    granted_by: optString,
    granted_at: ts,
    expires_at: optTs,
    revoked_at: optTs,
    revoked_reason: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_user_id_grant_kind_product_id", ["user_id", "grant_kind", "product_id"])
    .index("by_product_id", ["product_id"])
    .index("by_source_review_session_id", ["source_review_session_id"])
    .index("by_status_expires_at", ["status", "expires_at"])
    .index("by_user_id_status_expires_at", ["user_id", "status", "expires_at"]),

  // FK: report_id -> content_reports cascade
  moderation_actions: defineTable({
    id: uuid,
    report_id: optUuid,
    action_kind: literals(
      "hide",
      "remove",
      "restore",
      "reject_upload",
      "delete_storage",
      "create_pair_warning",
      "clear_pair_warning",
      "block_pair",
      "unblock_pair",
    ),
    status: literals("started", "applied", "partially_applied", "failed"),
    target_kind: optString,
    target_id: optUuid,
    previous_moderation_status: v.optional(moderationStatus),
    new_moderation_status: v.optional(moderationStatus),
    storage_action: v.optional(literals("none", "queued_delete", "deleted", "failed")),
    operator_kind: v.literal("operator"),
    operator_identifier: v.string(),
    reason: optString,
    notes: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_report_id_created_at", ["report_id", "created_at"]),

  // FK: recipient_user_id -> users cascade; target_device_id -> user_devices cascade
  notification_outbox: defineTable({
    id: uuid,
    recipient_user_id: uuid,
    target_device_id: uuid,
    push_token_hash: v.string(),
    apns_environment: apnsEnvironment,
    kind: notificationKind,
    payload_version: v.number(),
    redaction_level: literals("private", "generic", "content_allowed"),
    payload: v.any(),
    dedupe_key: optString,
    apns_push_type: literals("alert", "background"),
    apns_collapse_id: optString,
    provider_message_id: optString,
    last_error: optString,
    scheduled_for: ts,
    sent_at: optTs,
    failed_at: optTs,
    created_at: ts,
    title: optString,
    body: optString,
  })
    .index("by_uuid", ["id"])
    .index("by_dedupe_key", ["dedupe_key"])
    .index("by_recipient_user_id_created_at", ["recipient_user_id", "created_at"])
    .index("by_target_device_id", ["target_device_id"])
    .index("by_created_at", ["created_at"]),

  // FK: pair_id -> relationship_pairs restrict; source_report_id -> content_reports cascade
  pair_safety_warning_flags: defineTable({
    id: uuid,
    pair_id: uuid,
    source_report_id: optUuid,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_pair_id_created_at", ["pair_id", "created_at"])
    .index("by_pair_id_source_report_id", ["pair_id", "source_report_id"])
    .index("by_source_report_id", ["source_report_id"]),

  // FK: invite_id -> pairing_invites cascade. code_hash is unique.
  pairing_invite_secrets: defineTable({
    invite_id: uuid,
    code_hash: v.string(),
    created_at: ts,
  })
    .index("by_invite_id", ["invite_id"])
    .index("by_code_hash", ["code_hash"]),

  // FK: request_id -> privacy_requests restrict
  privacy_request_events: defineTable({
    id: uuid,
    request_id: uuid,
    actor_user_id: optUuid,
    event_kind: v.string(),
    metadata: v.any(),
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_request_id_created_at", ["request_id", "created_at"]),

  // FK: report_id -> content_reports cascade; source_media_asset_id -> media_assets set null
  report_snapshot_assets: defineTable({
    id: uuid,
    report_id: uuid,
    source_media_asset_id: optUuid,
    source_bucket: literals("profile-photos", "couple-media", "widget-drawings", "game-drawings"),
    source_storage_path: v.string(),
    bucket: v.literal("report-snapshots"),
    storage_path: v.string(),
    media_type: mediaType,
    byte_size: v.optional(v.number()),
    sha256: optString,
    copy_status: literals("pending_copy", "copied", "copy_failed"),
    copy_completed_at: optTs,
    last_copy_error: optString,
    delete_after: optTs,
    storage_delete_status: literals("none", "pending", "retrying", "deleted", "failed"),
    storage_deleted_at: optTs,
    storage_delete_attempts: v.number(),
    last_storage_delete_error: optString,
    storage_id: v.optional(v.id("_storage")),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_bucket_storage_path", ["bucket", "storage_path"])
    .index("by_delete_after_storage_delete_status", ["delete_after", "storage_delete_status"])
    .index("by_report_id_source_media_asset_id", ["report_id", "source_media_asset_id"])
    .index("by_source_media_asset_id", ["source_media_asset_id"])
    .index("by_storage_id", ["storage_id"])
    .index("by_storage_delete_status_storage_delete_attempts_updated_at", [
      "storage_delete_status",
      "storage_delete_attempts",
      "updated_at",
    ]),

  // FK: report_id -> content_reports cascade
  report_snapshots: defineTable({
    report_id: uuid,
    snapshot: v.any(),
    delete_after: optTs,
    created_at: ts,
  })
    .index("by_report_id", ["report_id"])
    .index("by_delete_after", ["delete_after"]),

  // code_hash is unique.
  review_access_codes: defineTable({
    id: uuid,
    code_hash: v.string(),
    seeded_partner_user_id: optUuid,
    scenario: reviewScenario,
    status: literals("active", "revoked", "expired"),
    expires_at: optTs,
    max_redemptions: v.number(),
    redemption_count: v.number(),
    created_at: ts,
    revoked_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_code_hash", ["code_hash"])
    .index("by_status_expires_at", ["status", "expires_at"]),

  // FK: code_id -> review_access_codes restrict; couple_id -> couples cascade; entitlement_grant_id -> entitlement_grants restrict
  review_access_sessions: defineTable({
    id: uuid,
    code_id: uuid,
    user_id: uuid,
    seeded_partner_user_id: optUuid,
    couple_id: optUuid,
    entitlement_grant_id: optUuid,
    scenario: reviewScenario,
    auth_verified_at: ts,
    redeemed_at: ts,
    user_agent: optString,
    app_version: optString,
    device_info: v.optional(v.any()),
  })
    .index("by_uuid", ["id"])
    .index("by_code_id_redeemed_at", ["code_id", "redeemed_at"])
    .index("by_couple_id", ["couple_id"])
    .index("by_entitlement_grant_id", ["entitlement_grant_id"])
    .index("by_user_id_redeemed_at", ["user_id", "redeemed_at"]),

  // FK: user_id -> users cascade
  review_demo_partners: defineTable({
    slot: v.number(),
    user_id: uuid,
    display_name: v.string(),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_slot", ["slot"])
    .index("by_user_id", ["user_id"]),

  // FK: raw_payload_id -> storekit_payloads restrict
  storekit_notification_events: defineTable({
    id: uuid,
    notification_uuid: uuid,
    notification_type: v.string(),
    subtype: optString,
    environment: storekitEnvironment,
    original_transaction_id: optString,
    raw_payload_id: optUuid,
    signed_payload: optString,
    received_at: ts,
    processed_at: optTs,
    processing_error: optString,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_notification_uuid", ["notification_uuid"])
    .index("by_raw_payload_id", ["raw_payload_id"]),

  storekit_payloads: defineTable({
    id: uuid,
    payload_kind: literals("transaction", "renewal_info", "server_notification", "server_api_response"),
    environment: storekitEnvironment,
    original_transaction_id: optString,
    transaction_id: optString,
    notification_uuid: optUuid,
    signed_payload: optString,
    payload_json: v.optional(v.any()),
    sha256: optString,
    received_at: ts,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_environment_sha256", ["environment", "sha256"]),

  // FK: product_id -> subscription_products restrict; raw_payload_id -> storekit_payloads restrict
  storekit_transactions: defineTable({
    id: uuid,
    user_id: uuid,
    product_id: uuid,
    environment: storekitEnvironment,
    app_account_token: optUuid,
    original_transaction_id: v.string(),
    transaction_id: v.string(),
    web_order_line_item_id: optString,
    status: literals("active", "grace", "billing_retry", "expired", "revoked", "refunded"),
    purchased_at: optTs,
    expires_at: optTs,
    revoked_at: optTs,
    revocation_reason: optString,
    // True when the purchase started with a free trial offer, read from the payload when recorded.
    // Stored only when true, so the trial reminder cron reads trials and no other row.
    is_free_trial: v.optional(v.boolean()),
    raw_payload_id: optUuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_environment_transaction_id", ["environment", "transaction_id"])
    .index("by_environment_original_transaction_id", ["environment", "original_transaction_id"])
    .index("by_product_id_user_id", ["product_id", "user_id"])
    .index("by_raw_payload_id", ["raw_payload_id"])
    .index("by_status_expires_at", ["status", "expires_at"])
    .index("by_is_free_trial_status_expires_at", ["is_free_trial", "status", "expires_at"])
    .index("by_user_id_status_expires_at", ["user_id", "status", "expires_at"]),

  // FK: couple_id -> couples cascade; product_id -> subscription_products restrict
  streak_restorations: defineTable({
    id: uuid,
    couple_id: uuid,
    purchaser_user_id: uuid,
    product_id: uuid,
    environment: storekitEnvironment,
    transaction_id: v.string(),
    original_transaction_id: optString,
    restored_count: v.number(),
    restorable_through_date: v.optional(date),
    purchased_at: optTs,
    restored_at: ts,
    raw_payload_id: optUuid,
    status: literals("applied", "refunded"),
    refunded_at: optTs,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_environment_transaction_id", ["environment", "transaction_id"])
    .index("by_couple_id_restored_at", ["couple_id", "restored_at"])
    .index("by_product_id", ["product_id"])
    .index("by_purchaser_user_id_restored_at", ["purchaser_user_id", "restored_at"])
    .index("by_raw_payload_id", ["raw_payload_id"]),

  // FK: recipient_user_id -> users cascade; target_widget_device_id -> widget_push_devices cascade
  widget_push_outbox: defineTable({
    id: uuid,
    recipient_user_id: uuid,
    target_widget_device_id: uuid,
    widget_push_token_hash: v.string(),
    apns_environment: apnsEnvironment,
    kind: v.literal("widget_updated"),
    payload: v.any(),
    dedupe_key: optString,
    apns_collapse_id: optString,
    provider_message_id: optString,
    last_error: optString,
    scheduled_for: ts,
    sent_at: optTs,
    failed_at: optTs,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_target_widget_device_id_dedupe_key", ["target_widget_device_id", "dedupe_key"])
    .index("by_recipient_user_id", ["recipient_user_id"])
    .index("by_created_at", ["created_at"]),

  // ---- public schema ----

  // FK: report_id -> content_reports cascade; every target id -> its row set null (see lib/reports.ts)
  content_report_targets: defineTable({
    report_id: uuid,
    target_kind: literals(
      "daily_answer",
      "memory",
      "memory_note",
      "memory_media",
      "thread_message",
      "thread_message_media",
      "widget_drawing_revision",
      "media_asset",
      "profile",
      "conduct",
    ),
    daily_answer_id: optUuid,
    memory_id: optUuid,
    memory_note_id: optUuid,
    memory_media_id: optUuid,
    message_id: optUuid,
    message_media_message_id: optUuid,
    message_media_asset_id: optUuid,
    widget_drawing_revision_id: optUuid,
    media_asset_id: optUuid,
    profile_user_id: optUuid,
    conduct_user_id: optUuid,
    created_at: ts,
    live_target_deleted_at: optTs,
  })
    .index("by_report_id", ["report_id"])
    .index("by_conduct_user_id", ["conduct_user_id"])
    .index("by_daily_answer_id", ["daily_answer_id"])
    .index("by_media_asset_id", ["media_asset_id"])
    .index("by_memory_id", ["memory_id"])
    .index("by_memory_media_id", ["memory_media_id"])
    .index("by_memory_note_id", ["memory_note_id"])
    .index("by_message_id", ["message_id"])
    .index("by_message_media_message_id_message_media_asset_id", [
      "message_media_message_id",
      "message_media_asset_id",
    ])
    .index("by_profile_user_id", ["profile_user_id"])
    .index("by_widget_drawing_revision_id", ["widget_drawing_revision_id"]),

  // FK: couple_id -> couples cascade; pair_id -> relationship_pairs restrict
  content_reports: defineTable({
    id: uuid,
    reporter_user_id: uuid,
    reported_user_id: uuid,
    couple_id: uuid,
    pair_id: uuid,
    reason: literals(
      "harassment",
      "abuse",
      "threat",
      "sexual_content",
      "hate",
      "privacy",
      "impersonation",
      "self_harm",
      "spam",
      "other",
    ),
    note: optString,
    status: literals("submitted", "under_review", "action_taken", "rejected", "closed"),
    block_requested: v.boolean(),
    leave_requested: v.boolean(),
    created_at: ts,
    updated_at: ts,
    resolved_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_created_at", ["couple_id", "created_at"])
    .index("by_pair_id", ["pair_id"])
    .index("by_reported_user_id_created_at", ["reported_user_id", "created_at"])
    .index("by_reporter_user_id_created_at", ["reporter_user_id", "created_at"])
    .index("by_status_created_at", ["status", "created_at"]),

  // FK: couple_id -> couples cascade; moderated_by -> users set null; moderation_report_id -> content_reports set null
  conversation_threads: defineTable({
    id: uuid,
    couple_id: uuid,
    kind: threadKind,
    created_by_user_id: uuid,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
    ...moderation,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_created_at", ["couple_id", "created_at"])
    .index("by_couple_id_moderation_status_deleted_at", ["couple_id", "moderation_status", "deleted_at"])
    .index("by_created_by_user_id", ["created_by_user_id"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"]),

  // FK: couple_id -> couples cascade; couple_day_id -> couple_days cascade. dedupe_key is unique.
  couple_activity_events: defineTable({
    id: uuid,
    couple_id: uuid,
    user_id: uuid,
    couple_day_id: uuid,
    activity_kind: activityKind,
    occurred_at: ts,
    dedupe_key: v.string(),
    metadata: v.any(),
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_dedupe_key", ["dedupe_key"])
    .index("by_couple_id_couple_day_id_activity_kind", ["couple_id", "couple_day_id", "activity_kind"])
    .index("by_couple_day_id", ["couple_day_id"])
    .index("by_user_id_created_at", ["user_id", "created_at"]),

  // FK: couple_id -> couples cascade. (couple_id, local_date) is unique.
  couple_days: defineTable({
    id: uuid,
    couple_id: uuid,
    local_date: date,
    anchor_time_zone_id: v.string(),
    starts_at: ts,
    ends_at: ts,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_local_date", ["couple_id", "local_date"])
    .index("by_couple_id_starts_at", ["couple_id", "starts_at"]),

  // FK: couple_id -> couples cascade. (couple_id, user_id) is unique; one active couple per user.
  couple_members: defineTable({
    couple_id: uuid,
    user_id: uuid,
    role: literals("creator", "partner"),
    status: memberStatus,
    // Either partner can set either member's birthday. It belongs to this relationship only.
    birthday: v.optional(date),
    joined_at: ts,
    left_at: optTs,
    ended_notice_seen_at: optTs,
    updated_at: ts,
  })
    .index("by_couple_id_user_id", ["couple_id", "user_id"])
    .index("by_couple_id_status", ["couple_id", "status"])
    .index("by_user_id_status_couple_id", ["user_id", "status", "couple_id"]),

  // FK: pair_id -> relationship_pairs restrict
  couples: defineTable({
    id: uuid,
    pair_id: uuid,
    status: relationshipStatus,
    started_on: v.optional(date),
    created_by_user_id: uuid,
    created_at: ts,
    updated_at: ts,
    ended_at: optTs,
    delete_after: optTs,
    // Set when the hard purge has removed the couple's content. The couple row stays.
    purged_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_pair_id_status", ["pair_id", "status"])
    .index("by_status_purged_at_delete_after", ["status", "purged_at", "delete_after"]),

  // FK: answer_id -> daily_question_answers cascade; media_asset_id -> media_assets cascade.
  // (answer_id, media_asset_id) and (answer_id, sort_order) are unique.
  daily_answer_media: defineTable({
    answer_id: uuid,
    media_asset_id: uuid,
    sort_order: v.number(),
  })
    .index("by_answer_id_media_asset_id", ["answer_id", "media_asset_id"])
    .index("by_answer_id_sort_order", ["answer_id", "sort_order"])
    .index("by_media_asset_id", ["media_asset_id"]),

  // FK: answer_id -> daily_question_answers cascade
  daily_answer_partner_choice: defineTable({
    answer_id: uuid,
    selected_user_id: uuid,
  })
    .index("by_answer_id", ["answer_id"])
    .index("by_selected_user_id", ["selected_user_id"]),

  // The option an `either_or` answer picked. FK: answer_id -> daily_question_answers cascade. answer_id is unique.
  daily_answer_option_choice: defineTable({
    answer_id: uuid,
    option: literals("a", "b"),
  }).index("by_answer_id", ["answer_id"]),

  // FK: answer_id -> daily_question_answers cascade
  daily_answer_text: defineTable({
    answer_id: uuid,
    body: v.string(),
  }).index("by_answer_id", ["answer_id"]),

  // FK: couple_day_id -> couple_days cascade. (couple_day_id, user_id) is unique.
  daily_challenges: defineTable({
    couple_day_id: uuid,
    user_id: uuid,
    completed_at: optTs,
    partner_notified_at: optTs,
  })
    .index("by_couple_day_id_user_id", ["couple_day_id", "user_id"])
    .index("by_user_id", ["user_id"]),

  // FK: instance_id -> daily_question_instances cascade. (instance_id, user_id) is unique.
  daily_question_answers: defineTable({
    id: uuid,
    instance_id: uuid,
    user_id: uuid,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
    ...moderation,
  })
    .index("by_uuid", ["id"])
    .index("by_instance_id_user_id", ["instance_id", "user_id"])
    .index("by_user_id_created_at", ["user_id", "created_at"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"]),

  // FK: couple_day_id -> couple_days cascade; question_version_id -> question_versions cascade; replaced_by_instance_id -> self set null.
  // Active slot is unique per (couple_day_id, seeded_for_user_id, slot_number) while status is active.
  daily_question_instances: defineTable({
    id: uuid,
    // Set on daily instances only. A topic instance has none, so day-based reads never see it.
    couple_day_id: optUuid,
    // Topic instances: the topic's collection, and the couple day the question was started on.
    // `started_couple_day_id` only dates topic rows. Daily code never reads it.
    topic_collection_id: optUuid,
    started_couple_day_id: optUuid,
    // The day's couple and the version's question, stored so a question's rounds are one index read.
    couple_id: uuid,
    question_id: uuid,
    question_version_id: uuid,
    seeded_for_user_id: uuid,
    slot_number: v.number(),
    status: literals("active", "shuffled", "answered"),
    replaced_by_instance_id: optUuid,
    replaced_at: optTs,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_day_id_seeded_for_user_id_status_slot_number", [
      "couple_day_id",
      "seeded_for_user_id",
      "status",
      "slot_number",
    ])
    .index("by_couple_day_id_question_version_id", ["couple_day_id", "question_version_id"])
    .index("by_couple_id_question_id", ["couple_id", "question_id"])
    .index("by_couple_id_topic_collection_id", ["couple_id", "topic_collection_id"])
    .index("by_question_version_id", ["question_version_id"])
    .index("by_replaced_by_instance_id", ["replaced_by_instance_id"])
    .index("by_seeded_for_user_id_status", ["seeded_for_user_id", "status"]),

  // FK: couple_id, couple_day_id, question_id, skipped_instance_id, replacement_instance_id, user_id all cascade
  daily_question_shuffles: defineTable({
    id: uuid,
    couple_id: uuid,
    couple_day_id: uuid,
    user_id: uuid,
    question_id: uuid,
    skipped_instance_id: uuid,
    replacement_instance_id: uuid,
    slot_number: v.number(),
    skipped_at: ts,
    exclude_until: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_day_id_user_id", ["couple_day_id", "user_id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_question_id", ["question_id"])
    .index("by_replacement_instance_id", ["replacement_instance_id"])
    .index("by_skipped_instance_id", ["skipped_instance_id"])
    .index("by_user_id_question_id_exclude_until", ["user_id", "question_id", "exclude_until"]),

  // One chat per question and couple, whatever version or instance the question comes back as.
  // FK: couple_id -> couples cascade; question_id -> questions cascade; thread_id -> conversation_threads cascade.
  // (couple_id, question_id) and thread_id are unique.
  daily_question_threads: defineTable({
    couple_id: uuid,
    question_id: uuid,
    thread_id: uuid,
    created_at: ts,
  })
    .index("by_couple_id_question_id", ["couple_id", "question_id"])
    .index("by_thread_id", ["thread_id"]),

  // FK: couple_id -> couples cascade; user_id -> users cascade. (couple_id, user_id) is unique.
  latest_partner_locations: defineTable({
    couple_id: uuid,
    user_id: uuid,
    latitude: v.number(),
    longitude: v.number(),
    accuracy_m: v.optional(v.number()),
    captured_at: ts,
    received_at: ts,
    updated_at: ts,
    source: locationSource,
    client_operation_id: uuid,
    client_id: uuid,
    client_sequence: v.number(),
  })
    .index("by_couple_id_user_id", ["couple_id", "user_id"])
    .index("by_user_id_updated_at", ["user_id", "updated_at"]),

  // One row per (couple_id, user_id). sent_total is what the user sent the partner, and seen_total is how
  // many of the partner's hearts the user was shown. They are on separate rows so a send and a mark
  // from the two partners never write the same row. The unseen count is the partner's sent_total minus
  // the user's seen_total. A row exists once the user has sent or seen a heart. FK: couple_id -> couples cascade;
  // sender_user_id -> users cascade. (couple_id, sender_user_id) is unique.
  couple_hearts: defineTable({
    couple_id: uuid,
    sender_user_id: uuid,
    sent_total: v.number(),
    seen_total: v.number(),
    last_sent_at: optTs,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_couple_id_sender_user_id", ["couple_id", "sender_user_id"]),

  // A couple's own countdowns ("Trip to Bergen"), next to the milestones derived from
  // couples.started_on. Either partner can add, edit, or delete one. target_date is a
  // calendar day, so each phone counts days in its own time zone. Delete sets deleted_at,
  // so a late save from the other phone cannot bring a deleted countdown back.
  // FK: couple_id -> couples cascade.
  countdowns: defineTable({
    id: uuid,
    couple_id: uuid,
    title: v.string(),
    target_date: date,
    created_by_user_id: uuid,
    last_edited_by_user_id: uuid,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_deleted_at", ["couple_id", "deleted_at"]),

  // A photo with an optional short caption that one partner posts as an "I thought about you"
  // check-in. The phone shows it in a ring on Home for 24 hours after created_at, then keeps it in
  // the Stories archive. The server stores no expiry. seen_at is when the partner first opened it.
  // Delete sets deleted_at and only the author may delete.
  // FK: couple_id -> couples cascade; author_user_id -> users cascade; media_asset_id -> media_assets restrict.
  stories: defineTable({
    id: uuid,
    couple_id: uuid,
    author_user_id: uuid,
    media_asset_id: uuid,
    caption: optString,
    created_at: ts,
    seen_at: optTs,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_created_at", ["couple_id", "created_at"])
    .index("by_media_asset_id", ["media_asset_id"]),

  // A partner's short note, shown in a bubble over their avatar on Home for 24 hours after
  // created_at. A new note replaces the old one, removing it deletes the row, and the
  // delete-expired-notes cron deletes it once its 24 hours are over.
  // FK: couple_id -> couples cascade; user_id -> users cascade. (couple_id, user_id) is unique.
  couple_notes: defineTable({
    couple_id: uuid,
    user_id: uuid,
    text: v.string(),
    created_at: ts,
  })
    .index("by_couple_id_user_id", ["couple_id", "user_id"])
    .index("by_created_at", ["created_at"]),

  // FK: couple_id -> couples cascade; user_id -> users cascade. (couple_id, user_id) is unique.
  location_sharing_preferences: defineTable({
    couple_id: uuid,
    user_id: uuid,
    is_enabled: v.boolean(),
    enabled_at: optTs,
    disabled_at: optTs,
    consent_version: optString,
    source: locationSource,
    // Sending moves while Paeonia is closed. Only true while sharing is on.
    // The phone restores it after a new sign-in.
    updates_while_closed: v.boolean(),
    // What the phone last reported, and the phone's time of that report. Never shown to the partner.
    location_permission: v.optional(locationPermission),
    device_state_reported_at: optTs,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_couple_id_user_id", ["couple_id", "user_id"])
    .index("by_user_id", ["user_id"]),

  // FK: couple_id -> couples cascade; moderated_by -> users set null; moderation_report_id -> content_reports set null.
  // (bucket, storage_path) is unique.
  media_assets: defineTable({
    id: uuid,
    owner_user_id: uuid,
    couple_id: optUuid,
    reserved_parent_kind: literals(
      "profile_photo",
      "memory_media",
      "daily_answer_media",
      "thread_message_media",
      "widget_drawing_revision",
      "game_move",
      "exquisite_corpse_part", // Exquisite corpse
      "story",
      "guess_my_spot_round", // Guess my spot
      "report_snapshot",
    ),
    reserved_parent_id: uuid,
    reserved_by_client_operation_id: uuid,
    bucket: mediaBucket,
    storage_path: v.string(),
    media_type: mediaType,
    upload_purpose: literals(
      "profile_photo",
      "memory_photo",
      "voice_note",
      "daily_answer_media",
      "thread_media",
      "widget_drawing_payload",
      "game_drawing_payload",
      "exquisite_corpse_drawing", // Exquisite corpse
      "exquisite_corpse_strip", // Exquisite corpse
      "story_photo",
      "guess_my_spot_photo", // Guess my spot
      "report_snapshot",
    ),
    expected_media_type: mediaType,
    expected_bucket: mediaBucket,
    mime_type: optString,
    byte_size: v.optional(v.number()),
    sha256: optString,
    width: v.optional(v.number()),
    height: v.optional(v.number()),
    duration_ms: v.optional(v.number()),
    upload_status: literals("pending", "finalized", "failed", "expired"),
    upload_expires_at: ts,
    upload_finalized_at: optTs,
    ...moderation,
    storage_delete_status: literals("none", "pending", "retrying", "deleted", "failed"),
    storage_deleted_at: optTs,
    storage_delete_attempts: v.number(),
    last_storage_delete_error: optString,
    // Convex file storage id. Set when the upload finishes.
    storage_id: v.optional(v.id("_storage")),
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_bucket_storage_path", ["bucket", "storage_path"])
    .index("by_couple_id_created_at", ["couple_id", "created_at"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_owner_user_id_created_at", ["owner_user_id", "created_at"])
    .index("by_reserved_parent_kind_reserved_parent_id", ["reserved_parent_kind", "reserved_parent_id"])
    .index("by_sha256", ["sha256"])
    .index("by_storage_delete_status_storage_delete_attempts_updated_at", [
      "storage_delete_status",
      "storage_delete_attempts",
      "updated_at",
    ])
    .index("by_storage_delete_status_updated_at", ["storage_delete_status", "updated_at"])
    .index("by_upload_status_upload_expires_at", ["upload_status", "upload_expires_at"])
    .index("by_storage_id", ["storage_id"]),

  // FK: couple_id -> couples cascade
  memories: defineTable({
    id: uuid,
    couple_id: uuid,
    title: v.string(),
    memory_date: date,
    // Where the memory happened, picked by a partner. City and country are stored with it so the
    // memories map can count places without looking addresses up.
    place: v.optional(
      v.object({
        name: v.string(),
        latitude: v.number(),
        longitude: v.number(),
        city: optString,
        country_code: optString,
      }),
    ),
    created_by_user_id: uuid,
    last_edited_by_user_id: uuid,
    revision: v.number(),
    ...moderation,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_memory_date_id", ["couple_id", "memory_date", "id"])
    .index("by_couple_id_updated_at_id", ["couple_id", "updated_at", "id"])
    .index("by_created_by_user_id", ["created_by_user_id"])
    .index("by_last_edited_by_user_id", ["last_edited_by_user_id"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_couple_id_moderation_status_deleted_at", ["couple_id", "moderation_status", "deleted_at"]),

  // FK: memory_id -> memories cascade; media_asset_id -> media_assets cascade. (memory_id, media_asset_id) is unique.
  // (memory_id, owner_user_id, sort_order) is unique while deleted_at is null.
  memory_media: defineTable({
    id: uuid,
    memory_id: uuid,
    media_asset_id: uuid,
    owner_user_id: uuid,
    sort_order: v.number(),
    ...moderation,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_memory_id_owner_user_id_sort_order", ["memory_id", "owner_user_id", "sort_order"])
    .index("by_memory_id_media_asset_id", ["memory_id", "media_asset_id"])
    .index("by_media_asset_id", ["media_asset_id"])
    .index("by_memory_id_sort_order", ["memory_id", "sort_order"])
    .index("by_memory_id_updated_at", ["memory_id", "updated_at"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_owner_user_id_memory_id", ["owner_user_id", "memory_id"])
    .index("by_memory_id_moderation_status_deleted_at", ["memory_id", "moderation_status", "deleted_at"]),

  // FK: memory_id -> memories cascade. (memory_id, user_id) is unique.
  memory_notes: defineTable({
    id: uuid,
    memory_id: uuid,
    user_id: uuid,
    body: v.string(),
    revision: v.number(),
    ...moderation,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_memory_id_user_id", ["memory_id", "user_id"])
    .index("by_memory_id_updated_at", ["memory_id", "updated_at"])
    .index("by_memory_id_moderation_status_deleted_at", ["memory_id", "moderation_status", "deleted_at"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_user_id_updated_at", ["user_id", "updated_at"]),

  // FK: memory_id -> memories cascade; thread_id -> conversation_threads cascade. Both unique.
  memory_threads: defineTable({
    memory_id: uuid,
    thread_id: uuid,
    created_at: ts,
  })
    .index("by_memory_id", ["memory_id"])
    .index("by_thread_id", ["thread_id"]),

  // The replies to one story. The partner's first reply starts the thread, and the thread outlives
  // the story's 24 hours on Home. Deleting the story deletes the thread (`delete_story`).
  // FK: story_id -> stories cascade; thread_id -> conversation_threads cascade. Both unique.
  story_threads: defineTable({
    story_id: uuid,
    thread_id: uuid,
    created_at: ts,
  })
    .index("by_story_id", ["story_id"])
    .index("by_thread_id", ["thread_id"]),

  // FK: user_id -> users cascade
  notification_preferences: defineTable({
    user_id: uuid,
    streak_reminders_enabled: v.boolean(),
    daily_challenge_enabled: v.boolean(),
    partner_answered_enabled: v.boolean(),
    widget_updates_enabled: v.boolean(),
    location_updates_enabled: v.boolean(),
    lock_screen_detail_level: literals("private", "descriptive"),
    revision: v.number(),
    created_at: ts,
    updated_at: ts,
    memories_enabled: v.boolean(),
    messages_enabled: v.boolean(),
    games_enabled: v.boolean(),
    // Opt-in "question time" reminder. `question_time_minutes` counts minutes after local midnight (0 to 1439).
    question_time_enabled: v.boolean(),
    question_time_minutes: v.number(),
  })
    .index("by_user_id", ["user_id"])
    .index("by_question_time_enabled", ["question_time_enabled"]),

  // FK: couple_id -> couples cascade
  pairing_invites: defineTable({
    id: uuid,
    created_by_user_id: uuid,
    status: literals("pending", "accepted", "revoked", "expired"),
    expires_at: ts,
    accepted_by_user_id: optUuid,
    accepted_at: optTs,
    revoked_at: optTs,
    couple_id: optUuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_created_by_user_id_status_expires_at", ["created_by_user_id", "status", "expires_at"])
    .index("by_status_expires_at", ["status", "expires_at"]),

  privacy_requests: defineTable({
    id: uuid,
    user_id: uuid,
    request_kind: literals("access", "export", "deletion", "correction"),
    status: literals("submitted", "verifying", "processing", "completed", "rejected", "cancelled"),
    requested_at: ts,
    verified_at: optTs,
    completed_at: optTs,
    cancelled_at: optTs,
    contact_email: optString,
    requester_note: optString,
    visible_status_message: optString,
    revision: v.number(),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_user_id_request_kind_status", ["user_id", "request_kind", "status"])
    .index("by_user_id_requested_at", ["user_id", "requested_at"])
    .index("by_user_id_updated_at_id", ["user_id", "updated_at", "id"]),

  // FK: user_id -> users cascade; profile_photo_asset_id -> media_assets set null;
  // provider_profile_photo_asset_id -> media_assets restrict; moderation_report_id -> content_reports set null
  profiles: defineTable({
    user_id: uuid,
    display_name: optString,
    profile_photo_asset_id: optUuid,
    time_zone_id: optString,
    time_zone_updated_at: optTs,
    onboarding_completed_at: optTs,
    revision: v.number(),
    ...moderation,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
    provider_profile_photo_asset_id: optUuid,
    provider_profile_photo_source: v.optional(v.literal("google")),
    // The person's answer to "Help us improve Paeonia?", when they gave it, and
    // which version of the question they saw. Missing until they answer.
    shares_usage: v.optional(v.boolean()),
    shares_usage_decided_at: optTs,
    shares_usage_notice: optString,
  })
    .index("by_user_id", ["user_id"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_profile_photo_asset_id", ["profile_photo_asset_id"])
    .index("by_provider_profile_photo_asset_id", ["provider_profile_photo_asset_id"])
    .index("by_updated_at_user_id", ["updated_at", "user_id"])
    // The admin user search.
    .searchIndex("search_display_name", { searchField: "display_name" }),

  // FK: question_version_id -> question_versions cascade. (question_version_id, answer_kind) is unique.
  question_answer_kinds: defineTable({
    question_version_id: uuid,
    answer_kind: literals("text", "photo", "voice", "partner_choice", "either_or"),
    created_at: ts,
  }).index("by_question_version_id_answer_kind", ["question_version_id", "answer_kind"]),

  // FK: couple_id -> couples cascade. At most one active system collection.
  question_collections: defineTable({
    id: uuid,
    kind: literals("system", "custom", "mini_game", "topic"),
    // Topics only: the stable topic key, the shelf order, and whether the topic stays off the lock
    // screen (Flirt): its chat pushes name only the sender.
    key: optString,
    sort_order: v.optional(v.number()),
    private: v.optional(v.boolean()),
    couple_id: optUuid,
    created_by_user_id: optUuid,
    status: literals("draft", "active", "retired", "archived"),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_created_by_user_id", ["created_by_user_id"])
    .index("by_kind_status", ["kind", "status"])
    .index("by_kind_key", ["kind", "key"]),

  // A topic's localized name. FK: collection_id -> question_collections cascade. (collection_id, locale) is unique.
  question_collection_localizations: defineTable({
    collection_id: uuid,
    locale: literals("en", "nb"),
    title: v.string(),
    subtitle: v.string(),
    created_at: ts,
    updated_at: ts,
  }).index("by_collection_id_locale", ["collection_id", "locale"]),

  // One row per active topic: its names and its ready questions with their current wording, in order.
  // Derived from question_collections, question_collection_localizations, questions, question_versions,
  // question_version_localizations and question_answer_kinds, so the topic reads load one row instead of
  // about eight per question. Only `rebuildTopicCatalogs` (lib/topicCatalog.ts) writes it, at the end of
  // `catalog:sync_catalog`. FK: collection_id -> question_collections. collection_id and key are unique.
  topic_catalog: defineTable({
    collection_id: uuid,
    key: v.string(),
    sort_order: v.number(),
    private: v.boolean(),
    title_en: v.string(),
    subtitle_en: v.string(),
    title_nb: v.string(),
    subtitle_nb: v.string(),
    questions: v.array(
      v.object({
        question_id: uuid,
        question_key: v.string(),
        question_version_id: uuid,
        sort_order: v.number(),
        prompt_en: v.string(),
        short_prompt_en: v.string(),
        prompt_nb: v.string(),
        short_prompt_nb: v.string(),
        answer_kinds: v.array(v.string()),
        option_a_en: optString,
        option_b_en: optString,
        option_a_nb: optString,
        option_b_nb: optString,
      }),
    ),
  })
    .index("by_collection_id", ["collection_id"])
    .index("by_key", ["key"]),

  // FK: question_version_id -> question_versions cascade. (question_version_id, locale) is unique.
  question_version_localizations: defineTable({
    question_version_id: uuid,
    locale: literals("en", "nb"),
    prompt: v.string(),
    short_prompt: v.string(),
    // The two labels of an `either_or` ("pick one of two") version. Set only when its kinds include either_or.
    option_a: optString,
    option_b: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_question_version_id_locale", ["question_version_id", "locale"])
    .index("by_locale", ["locale"]),

  // FK: question_id -> questions cascade. (question_id, version_number) is unique; one active version per question.
  question_versions: defineTable({
    id: uuid,
    question_id: uuid,
    version_number: v.number(),
    status: literals("draft", "active", "retired"),
    active_from: ts,
    retired_at: optTs,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_question_id_version_number", ["question_id", "version_number"])
    .index("by_question_id_status", ["question_id", "status"]),

  // FK: collection_id -> question_collections cascade. (collection_id, key) is unique.
  questions: defineTable({
    id: uuid,
    collection_id: uuid,
    key: v.string(),
    status: literals("draft", "active", "retired", "archived"),
    resurfaceable: v.boolean(),
    resurface_after_months: v.optional(v.number()),
    // Topic questions: the order inside the topic.
    sort_order: v.optional(v.number()),
    created_by_user_id: optUuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_collection_id_key", ["collection_id", "key"])
    .index("by_collection_id_status", ["collection_id", "status"])
    .index("by_created_by_user_id", ["created_by_user_id"]),

  // FK: pair_id -> relationship_pairs restrict; source_report_id -> content_reports set null.
  // One active block per (pair_id, blocked_by_user_id, blocked_user_id).
  relationship_blocks: defineTable({
    id: uuid,
    pair_id: uuid,
    blocked_by_user_id: uuid,
    blocked_user_id: uuid,
    source_report_id: optUuid,
    created_at: ts,
    revoked_at: optTs,
    revoked_by_user_id: optUuid,
    revoke_reason: v.optional(literals("user_unblocked", "moderation_unblocked", "admin_correction")),
  })
    .index("by_uuid", ["id"])
    .index("by_pair_id_revoked_at", ["pair_id", "revoked_at"])
    .index("by_pair_id_blocked_by_user_id_blocked_user_id", [
      "pair_id",
      "blocked_by_user_id",
      "blocked_user_id",
    ])
    .index("by_source_report_id", ["source_report_id"]),

  // (user_low_id, user_high_id) is unique and user_low_id < user_high_id.
  relationship_pairs: defineTable({
    id: uuid,
    user_low_id: uuid,
    user_high_id: uuid,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_user_low_id_user_high_id", ["user_low_id", "user_high_id"]),

  // FK: couple_id -> couples cascade
  relationship_sync_events: defineTable({
    id: uuid,
    user_id: uuid,
    couple_id: uuid,
    initiated_by_user_id: optUuid,
    event_kind: literals(
      "relationship_started",
      "relationship_updated",
      "relationship_ended",
      "relationship_deleted",
      "entitlement_lost",
      "entitlement_restored",
      "content_hidden",
      "content_cleanup_scheduled",
      "content_purged",
      "account_deletion_started",
      "account_deleted",
    ),
    reason: optString,
    occurred_at: ts,
    relationship_status: relationshipStatus,
    member_status: memberStatus,
    ended_at: optTs,
    delete_after: optTs,
    local_purge_scope: v.any(),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_created_at_id", ["couple_id", "created_at", "id"])
    .index("by_user_id_created_at_id", ["user_id", "created_at", "id"]),

  // FK: couple_id -> couples cascade; last_qualified_couple_day_id -> couple_days set null
  streak_states: defineTable({
    couple_id: uuid,
    current_count: v.number(),
    longest_count: v.number(),
    last_qualified_date: v.optional(date),
    last_qualified_couple_day_id: optUuid,
    next_activity_deadline_at: optTs,
    updated_at: ts,
    restorable_count: v.number(),
    restorable_through_date: v.optional(date),
    restore_deadline: optTs,
    restored_at: optTs,
    last_restore_transaction_id: optString,
    // The deadline the couple's last free freeze covered. A new freeze is ready FREEZE_COOLDOWN_DAYS later.
    freeze_used_at: optTs,
  })
    .index("by_couple_id", ["couple_id"])
    .index("by_last_qualified_couple_day_id", ["last_qualified_couple_day_id"])
    .index("by_next_activity_deadline_at", ["next_activity_deadline_at"]),

  // apple_product_id is unique.
  subscription_products: defineTable({
    id: uuid,
    apple_product_id: v.string(),
    kind: literals("couple_subscription", "streak_restore"),
    billing_period: literals("monthly", "yearly", "one_time"),
    is_active: v.boolean(),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_apple_product_id", ["apple_product_id"])
    .index("by_is_active_kind", ["is_active", "kind"]),

  // A topic question the couple put aside. It leaves the topic's total until either partner brings it back.
  // Stores no user id, so nobody can learn who skipped. FK: couple_id -> couples cascade; question_id -> questions cascade.
  // (couple_id, question_id) is unique.
  topic_question_skips: defineTable({
    couple_id: uuid,
    question_id: uuid,
    skipped_at: ts,
  }).index("by_couple_id_question_id", ["couple_id", "question_id"]),

  // New in Convex: how far each person has read a thread, for read receipts. One row per
  // (thread_id, user_id). FK: thread_id -> conversation_threads cascade; user_id -> users cascade.
  thread_read_states: defineTable({
    thread_id: uuid,
    user_id: uuid,
    last_read_message_id: uuid,
    // created_at of the last read message, so a later mark can only move forward.
    last_read_message_created_at: ts,
    read_at: ts,
  })
    .index("by_thread_id_user_id", ["thread_id", "user_id"])
    .index("by_user_id", ["user_id"]),

  // New in Convex: when each person first saw the partner's answer to a daily question,
  // for the "new" mark in the app and the read receipt on the answer. One row per
  // (instance_id, user_id), never moved forward.
  // FK: instance_id -> daily_question_instances cascade; couple_id -> couples cascade; user_id -> users cascade.
  daily_answer_seen_states: defineTable({
    instance_id: uuid,
    couple_id: uuid,
    user_id: uuid,
    seen_at: ts,
  })
    .index("by_instance_id_user_id", ["instance_id", "user_id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_user_id", ["user_id"]),

  // One person's emoji reaction to one thing the couple shares (lib/reactions.ts). `target_kind` names
  // the table of `target_id`. One row per (target_kind, target_id, user_id). Choosing another emoji
  // replaces it, and clearing deletes it. No foreign key: the content's own delete path, the day reset,
  // the relationship purge and account deletion remove the rows (`deleteReactionsOf` and friends).
  // couple_id -> couples cascade; user_id -> users cascade.
  reactions: defineTable({
    target_kind: reactionTargetKind,
    target_id: uuid,
    couple_id: uuid,
    user_id: uuid,
    emoji: v.string(),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_target_kind_target_id_user_id", ["target_kind", "target_id", "user_id"])
    .index("by_couple_id_target_kind", ["couple_id", "target_kind"])
    .index("by_user_id", ["user_id"]),

  // FK: message_id -> thread_messages cascade; media_asset_id -> media_assets cascade.
  // (message_id, media_asset_id) and (message_id, sort_order) are unique.
  thread_message_media: defineTable({
    message_id: uuid,
    media_asset_id: uuid,
    sort_order: v.number(),
  })
    .index("by_message_id_media_asset_id", ["message_id", "media_asset_id"])
    .index("by_message_id_sort_order", ["message_id", "sort_order"])
    .index("by_media_asset_id", ["media_asset_id"]),

  // FK: thread_id -> conversation_threads cascade. reply_to_message_id -> thread_messages
  // in the same thread, kept when that message is removed (the reader hides its text).
  // reply_to_answer_id -> daily_question_answers of the thread's question, kept the same way.
  // A message replies to one of the two at most.
  thread_messages: defineTable({
    id: uuid,
    thread_id: uuid,
    sender_user_id: uuid,
    body: optString,
    reply_to_message_id: optUuid,
    reply_to_answer_id: optUuid,
    created_at: ts,
    updated_at: ts,
    edited_at: optTs,
    deleted_at: optTs,
    ...moderation,
  })
    .index("by_uuid", ["id"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_sender_user_id_created_at", ["sender_user_id", "created_at"])
    .index("by_thread_id_created_at_id", ["thread_id", "created_at", "id"])
    .index("by_thread_id_moderation_status_deleted_at_created_at", [
      "thread_id",
      "moderation_status",
      "deleted_at",
      "created_at",
    ]),

  // FK: user_id -> users cascade. (push_token_hash, apns_environment) is unique while disabled_at is null.
  user_devices: defineTable({
    id: uuid,
    user_id: uuid,
    platform: literals("ios", "ipados"),
    push_token: v.string(),
    push_token_hash: v.string(),
    apns_environment: apnsEnvironment,
    locale: optString,
    time_zone_id: optString,
    app_version: optString,
    last_seen_at: ts,
    revision: v.number(),
    created_at: ts,
    updated_at: ts,
    disabled_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_push_token_hash_apns_environment_disabled_at", [
      "push_token_hash",
      "apns_environment",
      "disabled_at",
    ])
    .index("by_user_id_disabled_at", ["user_id", "disabled_at"])
    .index("by_user_id_updated_at_id", ["user_id", "updated_at", "id"]),

  // FK: couple_id -> couples cascade; active_revision_id -> widget_drawing_revisions set null. couple_id is unique.
  widget_canvases: defineTable({
    id: uuid,
    couple_id: uuid,
    active_revision_id: optUuid,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_active_revision_id", ["active_revision_id"]),

  // FK: canvas_id -> widget_canvases cascade; parent_revision_id -> self set null;
  // payload_media_asset_id -> media_assets cascade (unique)
  widget_drawing_revisions: defineTable({
    id: uuid,
    canvas_id: uuid,
    author_user_id: uuid,
    parent_revision_id: optUuid,
    format: v.literal("pkdrawing"),
    format_version: v.number(),
    payload_media_asset_id: uuid,
    payload_bytes: v.number(),
    uncompressed_bytes: v.number(),
    compression: literals("none", "gzip"),
    stroke_count: v.optional(v.number()),
    point_count: v.optional(v.number()),
    bounds: v.optional(v.any()),
    renderer_version: v.number(),
    client_decode_validated_at: ts,
    client_renderer_version: v.string(),
    client_validation_version: v.string(),
    ...moderation,
    created_at: ts,
    updated_at: ts,
    deleted_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_author_user_id_created_at", ["author_user_id", "created_at"])
    .index("by_canvas_id_created_at_id", ["canvas_id", "created_at", "id"])
    .index("by_canvas_id_updated_at_id", ["canvas_id", "updated_at", "id"])
    .index("by_moderated_by", ["moderated_by"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_parent_revision_id", ["parent_revision_id"])
    .index("by_payload_media_asset_id", ["payload_media_asset_id"]),

  // FK: user_id -> users cascade; drawing.media_asset_id -> media_assets restrict. One row per user.
  // What the inviter makes before their partner joins (firstDay.ts). accept_pairing_invite turns it
  // into couple content and deletes the row.
  first_day_drafts: defineTable({
    user_id: uuid,
    started_on: v.optional(date),
    // Picked once by start_first_day_draft. The slot is the index + 1.
    question_version_ids: v.array(uuid),
    answers: v.array(v.object({ question_version_id: uuid, body: v.string(), answered_at: ts })),
    drawing: v.optional(
      v.object({
        media_asset_id: uuid,
        // The revision id the drawing gets on the couple's canvas: the asset's reserved_parent_id.
        revision_id: uuid,
        payload_bytes: v.number(),
        uncompressed_bytes: v.number(),
        compression: literals("none", "gzip"),
        stroke_count: v.optional(v.number()),
        point_count: v.optional(v.number()),
        bounds: v.optional(v.any()),
        sha256: v.string(),
        client_decode_validated_at: ts,
        client_renderer_version: v.string(),
        client_validation_version: v.string(),
        saved_at: ts,
      }),
    ),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_user_id", ["user_id"])
    .index("by_drawing_media_asset_id", ["drawing.media_asset_id"]),

  // ---- games (new in Convex, see games.ts and docs/games/draw-and-guess.md) ----
  // Every games table has a couple_id index. Relationship cleanup deletes the rows (lib/gameRegistry.ts).
  // game_settings, game_invites, and game_plays are shared by every game kind. The presence component keeps who
  // has a game open (lib/presence.ts). games, game_moves, game_guesses, game_round_stars, and
  // game_used_words belong to Draw & Guess (lib/drawAndGuess.ts).

  // FK: couple_id -> couples cascade. couple_id is unique. Shared by all games.
  game_settings: defineTable({
    couple_id: uuid,
    play_style: gamePlayStyle,
    language: gameLanguage,
    updated_by_user_id: uuid,
    // Who has seen the settings: whoever set them, and a partner who tapped through what the other
    // picked. The app shows that moment once, to a partner who is not in this list.
    seen_by_user_ids: v.array(uuid),
    created_at: ts,
    updated_at: ts,
  }).index("by_couple_id", ["couple_id"]),

  // FK: couple_id -> couples cascade. (couple_id, kind) is unique.
  games: defineTable({
    id: uuid,
    couple_id: uuid,
    kind: v.literal("draw_and_guess"),
    // choosing_word: the drawer picks a word. drawing: a round is open and the drawer draws.
    // guessing: the drawing is sent and the guesser guesses. turn_user_id is the person who acts next.
    state: literals("choosing_word", "drawing", "guessing"),
    turn_user_id: uuid,
    turn_number: v.number(),
    current_round_id: optUuid,
    // Three fixed choices, only while state is choosing_word. Only the drawer may read them.
    word_choices: v.optional(
      v.array(v.object({ difficulty: wordDifficulty, word_id: v.string(), word: v.string() })),
    ),
    // Always kept: the shared total (word points) and each partner's own total (word points plus the speed bonus).
    shared_points: v.number(),
    points_by_user: v.record(v.string(), v.number()),
    turn_started_at: ts,
    turn_reminder_sent_at: optTs,
    version: v.number(),
    created_by_user_id: uuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_kind", ["couple_id", "kind"])
    .index("by_turn_reminder_sent_at_turn_started_at", ["turn_reminder_sent_at", "turn_started_at"]),

  // FK: game_id -> games cascade. One row per round. (game_id, round_number) is unique.
  game_moves: defineTable({
    id: uuid,
    game_id: uuid,
    couple_id: uuid,
    round_number: v.number(),
    drawer_user_id: uuid,
    guesser_user_id: uuid,
    state: literals("drawing", "guessing", "solved", "missed"),
    difficulty: literals("easy", "medium", "hard", "custom"),
    // Absent for a custom word.
    word_id: optString,
    // Lowercase, single spaces.
    word: v.string(),
    points: v.number(),
    // FK: media_assets restrict. A pkdrawing in the game-drawings bucket.
    drawing_media_asset_id: optUuid,
    drawing_submitted_at: optTs,
    guesser_first_seen_at: optTs,
    started_at: ts,
    ended_at: optTs,
    solve_ms: v.optional(v.number()),
    // Guesser bonuses of a solve: 0, 1, or 2 for speed, 0 or 1 for the first try.
    speed_bonus: v.number(),
    first_try_bonus: v.optional(v.number()),
    // Letters the guesser's hints showed before the correct guess. Set on a solve. Any hint zeroes both bonuses.
    hints_used: v.optional(v.number()),
    // True when this hint-free solve beat every earlier hint-free solve by the same guesser. Fixed at solve time.
    personal_best: v.optional(v.boolean()),
    // When each partner first dismissed the finished round's result. The first time wins.
    drawer_result_seen_at: optTs,
    guesser_result_seen_at: optTs,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_game_id_round_number", ["game_id", "round_number"])
    .index("by_couple_id", ["couple_id"])
    .index("by_drawing_media_asset_id", ["drawing_media_asset_id"]),

  // FK: move_id -> game_moves cascade
  game_guesses: defineTable({
    id: uuid,
    move_id: uuid,
    couple_id: uuid,
    user_id: uuid,
    // Trimmed, lowercase, single spaces.
    text: v.string(),
    correct: v.boolean(),
    created_at: ts,
  })
    .index("by_move_id_created_at", ["move_id", "created_at"])
    .index("by_couple_id", ["couple_id"]),

  // FK: move_id -> game_moves cascade. (move_id, user_id) is unique. A partner's private star on a finished round. Nobody else is told.
  // round_number repeats the round's number so one user's stars page by round without reading the rounds.
  game_round_stars: defineTable({
    couple_id: uuid,
    move_id: uuid,
    user_id: uuid,
    round_number: v.number(),
    created_at: ts,
  })
    .index("by_move_id_user_id", ["move_id", "user_id"])
    .index("by_couple_id_user_id_round_number", ["couple_id", "user_id", "round_number"]),

  // FK: game_id -> games cascade. Words already shown to the couple.
  game_used_words: defineTable({
    game_id: uuid,
    couple_id: uuid,
    language: gameLanguage,
    difficulty: wordDifficulty,
    word_id: v.string(),
    created_at: ts,
  })
    .index("by_game_id_language_difficulty", ["game_id", "language", "difficulty"])
    .index("by_couple_id", ["couple_id"]),

  // The last invite each partner sent. (couple_id, kind, sender_user_id) is unique.
  game_invites: defineTable({
    couple_id: uuid,
    kind: gameKind,
    sender_user_id: uuid,
    sent_at: ts,
    // When the partner first opened the game after this invite. A new invite clears it.
    answered_at: optTs,
  }).index("by_couple_id_kind_sender_user_id", ["couple_id", "kind", "sender_user_id"]),

  // When either partner last had each game open, so the Games tab lists the games played most
  // recently first. A kind without a row was never opened. (couple_id, kind) is unique.
  game_plays: defineTable({
    couple_id: uuid,
    kind: gameKind,
    last_played_at: ts,
  }).index("by_couple_id_kind", ["couple_id", "kind"]),

  // Story Chain (storyChain.ts, lib/storyChain.ts). Rows are deleted with the couple's other game
  // rows through the game registry.

  // FK: couple_id -> couples cascade. couple_id is unique: one game per couple.
  story_chain_games: defineTable({
    id: uuid,
    couple_id: uuid,
    state: literals("choosing_opening", "writing", "titling"),
    turn_user_id: uuid,
    turn_number: v.number(),
    current_story_id: optUuid,
    story_count: v.number(),
    finished_count: v.number(),
    turn_started_at: ts,
    turn_reminder_sent_at: optTs,
    version: v.number(),
    created_by_user_id: uuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_turn_reminder_sent_at_turn_started_at", ["turn_reminder_sent_at", "turn_started_at"]),

  // FK: game_id -> story_chain_games cascade, couple_id -> couples cascade. (game_id, story_number) is unique.
  // `lines` holds at most 20 lines of at most 240 characters, so a story stays small.
  story_chain_stories: defineTable({
    id: uuid,
    game_id: uuid,
    couple_id: uuid,
    story_number: v.number(),
    starter_user_id: uuid,
    opening_id: optString,
    opening_text: optString,
    state: literals("writing", "titling", "finished"),
    lines: v.array(
      v.object({
        id: uuid,
        number: v.number(),
        author_user_id: uuid,
        text: v.string(),
        // The word this line gave to the next line.
        dare_word: optString,
        dare_word_id: optString,
        created_at: ts,
      }),
    ),
    last_line_user_id: optUuid,
    title: optString,
    titled_by_user_id: optUuid,
    finished_at: optTs,
    // The partners who have seen the finished story.
    seen_by: v.array(uuid),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_game_id_story_number", ["game_id", "story_number"])
    .index("by_couple_id_story_number", ["couple_id", "story_number"]),

  // FK: story_id -> story_chain_stories cascade. (story_id, user_id) is unique. Private to user_id.
  story_chain_stars: defineTable({
    couple_id: uuid,
    story_id: uuid,
    user_id: uuid,
    story_number: v.number(),
    created_at: ts,
  })
    .index("by_story_id_user_id", ["story_id", "user_id"])
    .index("by_couple_id_user_id_story_number", ["couple_id", "user_id", "story_number"]),

  // The openings and dare words a couple has used, per language. A kind starts over when used up.
  story_chain_used: defineTable({
    game_id: uuid,
    couple_id: uuid,
    language: gameLanguage,
    kind: literals("opening", "word"),
    content_id: v.string(),
    created_at: ts,
  })
    .index("by_game_id_language_kind", ["game_id", "language", "kind"])
    .index("by_couple_id", ["couple_id"]),
  // Mind Meld: mind_meld_games, mind_meld_rounds, mind_meld_words (lib/mindMeld.ts, docs/games/mind-meld.md).
  ...mindMeldTables,
  // Consensio: consensio_games, consensio_rounds, consensio_used_topics (lib/consensio.ts, docs/games/consensio.md).
  ...consensioTables,
  // Guess my spot: guess_my_spot_games, guess_my_spot_rounds (lib/guessMySpot.ts, docs/games/guess-my-spot.md).
  ...guessMySpotTables,
  // Exquisite corpse (docs/games/exquisite-corpse.md). Four tables, deleted with the couple's other game rows (lib/exquisiteCorpse.ts).
  // FK: couple_id -> couples cascade. couple_id is unique. part_index (0 head, 1 body, 2 legs) is the next part.
  exquisite_corpse_games: defineTable({
    id: uuid,
    couple_id: uuid,
    created_by_user_id: uuid,
    turn_user_id: uuid,
    turn_started_at: ts,
    turn_reminder_sent_at: optTs,
    figure_id: optUuid,
    figure_number: v.number(),
    part_index: v.number(),
    figures_finished: v.number(),
    version: v.number(),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_turn_reminder_sent_at_turn_started_at", ["turn_reminder_sent_at", "turn_started_at"]),

  // FK: game_id -> exquisite_corpse_games cascade. The client makes the id. The reveal seen times keep the first write.
  exquisite_corpse_figures: defineTable({
    id: uuid,
    couple_id: uuid,
    game_id: uuid,
    number: v.number(),
    starter_user_id: uuid,
    created_at: ts,
    finished_at: optTs,
    starter_reveal_seen_at: optTs,
    partner_reveal_seen_at: optTs,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_game_id_number", ["game_id", "number"])
    .index("by_couple_id_number", ["couple_id", "number"]),

  // FK: figure_id -> exquisite_corpse_figures cascade; media_assets restrict. The client makes the id. The strip is for the head and body only.
  exquisite_corpse_parts: defineTable({
    id: uuid,
    couple_id: uuid,
    game_id: uuid,
    figure_id: uuid,
    figure_number: v.number(),
    part_index: v.number(),
    drawer_user_id: uuid,
    drawing_media_asset_id: uuid,
    strip_media_asset_id: optUuid,
    idea_id: optString,
    idea_text: optString,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_figure_id_part_index", ["figure_id", "part_index"])
    .index("by_drawing_media_asset_id", ["drawing_media_asset_id"])
    .index("by_strip_media_asset_id", ["strip_media_asset_id"])
    .index("by_couple_id", ["couple_id"]),

  // FK: figure_id -> exquisite_corpse_figures cascade. (user_id, figure_id) is unique. A private star. figure_number lets stars page.
  exquisite_corpse_stars: defineTable({
    couple_id: uuid,
    user_id: uuid,
    figure_id: uuid,
    figure_number: v.number(),
    created_at: ts,
  })
    .index("by_couple_id_user_id_figure_number", ["couple_id", "user_id", "figure_number"])
    .index("by_user_id_figure_id", ["user_id", "figure_id"]),

  // FK: couple_id -> couples cascade. (couple_id, kind) is unique. One row per couple and board game: the current
  // game, the couple's tallies, and the last finished game (see boardGames.ts and docs/games/board-games.md).
  board_games: defineTable({
    id: uuid,
    couple_id: uuid,
    kind: literals("connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo"),
    // Starts at 1 and goes up with every rematch.
    game_number: v.number(),
    status: literals("playing", "finished"),
    // Player one of the current game. Player one moves first.
    first_user_id: uuid,
    // The move indexes in order. The board comes from replaying them with the kind's rules.
    moves: v.array(v.number()),
    // Absent once the game is finished.
    turn_user_id: optUuid,
    // Absent for a draw and while playing.
    winner_user_id: optUuid,
    win_line: v.array(v.number()),
    // Written with the first move by the starter. 1 to 60 characters on one line.
    stake: optString,
    stake_by_user_id: optUuid,
    // Ludo only. Each partner's piece color by user id, always two different colors. It stays across rematches, and a partner changes theirs with the first move of a game.
    colors_by_user: v.optional(v.record(v.string(), literals(...LUDO_COLORS))),
    // FK: media_assets. The hidden photo of a dots_and_boxes game. Nothing is cascaded: every read checks that the photo is still visible.
    photo_media_asset_id: optUuid,
    // The last finished game, kept after a rematch starts so a partner who missed the ending can see it.
    previous: v.optional(
      v.object({
        game_number: v.number(),
        first_user_id: uuid,
        moves: v.array(v.number()),
        winner_user_id: optUuid,
        win_line: v.array(v.number()),
        stake: optString,
        photo_media_asset_id: optUuid,
        finished_at: ts,
      }),
    ),
    // Tallies never reset. Keyed by user id.
    wins_by_user: v.record(v.string(), v.number()),
    draws: v.number(),
    games_finished: v.number(),
    started_at: ts,
    finished_at: optTs,
    turn_started_at: ts,
    // Set once the 72-hour reminder went out for the turn, and when the game ends so no reminder follows.
    turn_reminder_sent_at: optTs,
    version: v.number(),
    created_by_user_id: uuid,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_kind", ["couple_id", "kind"])
    .index("by_turn_reminder_sent_at_turn_started_at", ["turn_reminder_sent_at", "turn_started_at"]),

  // FK: couple_id -> couples cascade. (couple_id, kind, game_number) is unique.
  // Every finished board game, written by the move that ends it, so the couple can look back and watch it again.
  board_game_history: defineTable({
    couple_id: uuid,
    kind: literals("connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo"),
    game_number: v.number(),
    first_user_id: uuid,
    moves: v.array(v.number()),
    // Absent for a draw.
    winner_user_id: optUuid,
    win_line: v.array(v.number()),
    stake: optString,
    started_at: ts,
    finished_at: ts,
  }).index("by_couple_id_kind_game_number", ["couple_id", "kind", "game_number"]),

  // FK: couple_id -> couples cascade; user_id -> users cascade. (couple_id, user_id) is unique.
  // A partner's own mark for all board games, as base64 PKDrawing data.
  board_game_marks: defineTable({
    couple_id: uuid,
    user_id: uuid,
    drawing: v.string(),
    created_at: ts,
    updated_at: ts,
  }).index("by_couple_id_user_id", ["couple_id", "user_id"]),

  // FK: user_id -> users cascade. (widget_push_token_hash, apns_environment, widget_kind) is unique while disabled_at is null.
  widget_push_devices: defineTable({
    id: uuid,
    user_id: uuid,
    widget_kind: v.string(),
    widget_push_token: v.string(),
    widget_push_token_hash: v.string(),
    apns_environment: apnsEnvironment,
    locale: optString,
    time_zone_id: optString,
    app_version: optString,
    last_seen_at: ts,
    revision: v.number(),
    created_at: ts,
    updated_at: ts,
    disabled_at: optTs,
  })
    .index("by_uuid", ["id"])
    .index("by_token_hash_apns_environment_widget_kind_disabled_at", [
      "widget_push_token_hash",
      "apns_environment",
      "widget_kind",
      "disabled_at",
    ])
    .index("by_user_id_disabled_at", ["user_id", "disabled_at"]),
});
