import { checkViolation } from "./errors";
import type { WriterCtx } from "./db";
import { jsonbByteLength } from "./json";
import { newUuid } from "./ids";
import { nowIso } from "./time";

export type SyncEventKind =
  | "relationship_started"
  | "relationship_updated"
  | "relationship_ended"
  | "relationship_deleted"
  | "entitlement_lost"
  | "entitlement_restored"
  | "content_hidden"
  | "content_cleanup_scheduled"
  | "content_purged"
  | "account_deletion_started"
  | "account_deleted";

export type RelationshipSyncEventInput = {
  user_id: string;
  couple_id: string;
  initiated_by_user_id?: string | null;
  event_kind: SyncEventKind;
  reason?: string | null;
  relationship_status: "active" | "ended" | "deleted";
  member_status: "active" | "left" | "ended_notice_pending" | "ended_notice_seen";
  ended_at?: string | null;
  delete_after?: string | null;
  local_purge_scope?: Record<string, unknown> | null;
};

/** Port of `internal.create_relationship_sync_event`. Returns the new event id. */
export async function createRelationshipSyncEvent(
  ctx: WriterCtx,
  input: RelationshipSyncEventInput,
): Promise<string> {
  const scope = input.local_purge_scope ?? {};
  if (jsonbByteLength(scope) > 4096) {
    checkViolation("relationship_sync_events", "relationship_sync_events_local_purge_scope_check");
  }
  if (input.reason != null && (input.reason.length < 1 || input.reason.length > 160)) {
    checkViolation("relationship_sync_events", "relationship_sync_events_reason_check");
  }
  const now = nowIso();
  const id = newUuid();
  await ctx.db.insert("relationship_sync_events", {
    id,
    user_id: input.user_id,
    couple_id: input.couple_id,
    initiated_by_user_id: input.initiated_by_user_id ?? undefined,
    event_kind: input.event_kind,
    reason: input.reason ?? undefined,
    occurred_at: now,
    relationship_status: input.relationship_status,
    member_status: input.member_status,
    ended_at: input.ended_at ?? undefined,
    delete_after: input.delete_after ?? undefined,
    local_purge_scope: scope,
    created_at: now,
    updated_at: now,
  });
  return id;
}
