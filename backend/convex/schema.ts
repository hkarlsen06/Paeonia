import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  activityKind,
  apnsEnvironment,
  authProvider,
  literals,
  mediaBucket,
  mediaType,
  memberStatus,
  moderationStatus,
  notificationKind,
  relationshipStatus,
  reviewScenario,
  storekitEnvironment,
  locationSource,
} from "./lib/validators";

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
  })
    .index("by_uuid", ["id"])
    .index("by_clerk_user_id", ["clerk_user_id"]),

  // ---- internal schema ----

  // FK: request_id -> privacy_requests restrict
  account_deletion_jobs: defineTable({
    id: uuid,
    request_id: uuid,
    user_id: uuid,
    auth_provider: authProvider,
    status: literals(
      "ready_for_auth_delete",
      "processing_auth_delete",
      "attention_required",
      "completed",
    ),
    provider_revocation_status: literals("not_required", "succeeded", "manual_required"),
    provider_revocation_attempted_at: optTs,
    provider_revocation_error_code: optString,
    auth_delete_attempts: v.number(),
    next_attempt_at: optTs,
    claimed_at: optTs,
    last_auth_delete_error_code: optString,
    completed_at: optTs,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_request_id", ["request_id"])
    .index("by_user_id", ["user_id"])
    .index("by_status_next_attempt_at", ["status", "next_attempt_at"]),

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
    .index("by_status_locked_until", ["status", "locked_until"])
    .index("by_status_completed_at", ["status", "completed_at"])
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

  // FK: report_id -> content_reports cascade; reviewer_user_id -> users set null
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
    operator_kind: literals("service_role", "sql_runbook", "edge_function", "admin_user"),
    operator_identifier: v.string(),
    reviewer_user_id: optUuid,
    runbook_id: optString,
    reason: optString,
    notes: optString,
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_report_id_created_at", ["report_id", "created_at"])
    .index("by_reviewer_user_id", ["reviewer_user_id"]),

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
    attempt_count: v.number(),
    last_attempt_at: optTs,
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
    // Pending work: eq(sent_at, undefined).eq(failed_at, undefined).gte(scheduled_for, ...)
    .index("by_sent_at_failed_at_scheduled_for", ["sent_at", "failed_at", "scheduled_for"])
    .index("by_recipient_user_id_created_at", ["recipient_user_id", "created_at"])
    .index("by_target_device_id", ["target_device_id"]),

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

  // FK: matched_invite_id -> pairing_invites set null
  pairing_invite_attempts: defineTable({
    id: uuid,
    code_hash_prefix: v.string(),
    matched_invite_id: optUuid,
    user_id: optUuid,
    success: v.boolean(),
    failure_reason: optString,
    ip_hash: optString,
    device_hash: optString,
    app_version: optString,
    attempted_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_code_hash_prefix_attempted_at", ["code_hash_prefix", "attempted_at"])
    .index("by_matched_invite_id", ["matched_invite_id"])
    .index("by_user_id_attempted_at", ["user_id", "attempted_at"]),

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
    source_bucket: literals("profile-photos", "couple-media", "widget-drawings"),
    source_storage_path: v.string(),
    bucket: v.literal("report-snapshots"),
    storage_path: v.string(),
    media_type: mediaType,
    byte_size: v.optional(v.number()),
    sha256: optString,
    copy_status: literals("pending_copy", "copying", "copied", "copy_failed"),
    copy_claimed_at: optTs,
    copy_attempts: v.number(),
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
    .index("by_report_id", ["report_id"])
    .index("by_bucket_storage_path", ["bucket", "storage_path"])
    .index("by_copy_status_copy_attempts_copy_claimed_at_created_at", [
      "copy_status",
      "copy_attempts",
      "copy_claimed_at",
      "created_at",
    ])
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

  // FK: matched_code_id -> review_access_codes set null
  review_access_attempts: defineTable({
    id: uuid,
    user_id: uuid,
    code_hash_prefix: v.string(),
    matched_code_id: optUuid,
    success: v.boolean(),
    failure_reason: optString,
    ip_hash: optString,
    device_hash: optString,
    app_version: optString,
    attempted_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_code_hash_prefix_attempted_at", ["code_hash_prefix", "attempted_at"])
    .index("by_matched_code_id", ["matched_code_id"])
    .index("by_user_id_attempted_at", ["user_id", "attempted_at"]),

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
    completed_at: optTs,
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
    raw_payload_id: optUuid,
    last_reconciled_at: optTs,
    created_at: ts,
    updated_at: ts,
    reconciliation_claimed_at: optTs,
    reconciliation_attempts: v.number(),
    last_reconciliation_error: optString,
  })
    .index("by_uuid", ["id"])
    .index("by_environment_transaction_id", ["environment", "transaction_id"])
    .index("by_environment_original_transaction_id", ["environment", "original_transaction_id"])
    .index("by_product_id_user_id", ["product_id", "user_id"])
    .index("by_raw_payload_id", ["raw_payload_id"])
    .index("by_status_expires_at_last_reconciled_at_claimed_at", [
      "status",
      "expires_at",
      "last_reconciled_at",
      "reconciliation_claimed_at",
    ])
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
    attempt_count: v.number(),
    last_attempt_at: optTs,
    last_error: optString,
    scheduled_for: ts,
    sent_at: optTs,
    failed_at: optTs,
    created_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_sent_at_failed_at_scheduled_for", ["sent_at", "failed_at", "scheduled_for"])
    .index("by_target_widget_device_id_dedupe_key", ["target_widget_device_id", "dedupe_key"])
    .index("by_recipient_user_id", ["recipient_user_id"]),

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
    kind: literals("daily_question", "memory"),
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
  })
    .index("by_uuid", ["id"])
    .index("by_pair_id_status", ["pair_id", "status"])
    .index("by_status_delete_after", ["status", "delete_after"]),

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
    couple_day_id: uuid,
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

  // FK: instance_id -> daily_question_instances cascade; thread_id -> conversation_threads cascade. Both unique.
  daily_question_threads: defineTable({
    instance_id: uuid,
    thread_id: uuid,
    created_at: ts,
  })
    .index("by_instance_id", ["instance_id"])
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

  // FK: couple_id -> couples cascade; user_id -> users cascade. (couple_id, user_id) is unique.
  location_sharing_preferences: defineTable({
    couple_id: uuid,
    user_id: uuid,
    is_enabled: v.boolean(),
    enabled_at: optTs,
    disabled_at: optTs,
    consent_version: optString,
    source: locationSource,
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
  }).index("by_user_id", ["user_id"]),

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
  })
    .index("by_user_id", ["user_id"])
    .index("by_moderation_report_id", ["moderation_report_id"])
    .index("by_profile_photo_asset_id", ["profile_photo_asset_id"])
    .index("by_provider_profile_photo_asset_id", ["provider_profile_photo_asset_id"])
    .index("by_updated_at_user_id", ["updated_at", "user_id"]),

  // FK: question_version_id -> question_versions cascade. (question_version_id, answer_kind) is unique.
  question_answer_kinds: defineTable({
    question_version_id: uuid,
    answer_kind: literals("text", "photo", "voice", "partner_choice"),
    created_at: ts,
  }).index("by_question_version_id_answer_kind", ["question_version_id", "answer_kind"]),

  // FK: couple_id -> couples cascade. At most one active system collection.
  question_collections: defineTable({
    id: uuid,
    kind: literals("system", "custom", "mini_game"),
    couple_id: optUuid,
    created_by_user_id: optUuid,
    status: literals("draft", "active", "retired", "archived"),
    created_at: ts,
    updated_at: ts,
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_created_by_user_id", ["created_by_user_id"])
    .index("by_kind_status", ["kind", "status"]),

  // FK: question_version_id -> question_versions cascade. (question_version_id, locale) is unique.
  question_version_localizations: defineTable({
    question_version_id: uuid,
    locale: literals("en", "nb"),
    prompt: v.string(),
    short_prompt: v.string(),
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
    restore_available: v.boolean(),
    next_activity_deadline_at: optTs,
    updated_at: ts,
    restorable_count: v.number(),
    restorable_through_date: v.optional(date),
    restore_deadline: optTs,
    restored_at: optTs,
    last_restore_transaction_id: optString,
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

  // FK: thread_id -> conversation_threads cascade
  thread_messages: defineTable({
    id: uuid,
    thread_id: uuid,
    sender_user_id: uuid,
    body: optString,
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
