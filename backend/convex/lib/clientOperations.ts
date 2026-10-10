import { assertNoPendingAccountDeletion } from "./accountDeletion";
import { requestHash, sha256Hex } from "./crypto";
import type { WriterCtx } from "./db";
import { checkViolation, fail } from "./errors";
import { stableStringify } from "./json";
import { newUuid } from "./ids";
import { nowIso } from "./time";

export type ClientOperationInput = {
  client_operation_id: string;
  client_id: string;
  client_sequence: number;
  local_created_at: string;
  operation_kind: string;
  idempotency_scope: string;
  /** The request fields the SQL function hashed. Hashed with a stable JSON encoding. */
  request: unknown;
};

/**
 * Port of `begin_client_operation` + `complete_client_operation`.
 *
 * A mutation is one transaction, so begin, the work, and complete commit
 * together. If `work` throws, the whole mutation rolls back and no operation
 * row remains, so the client can retry.
 *
 * Returns the stored response. On a replay of a succeeded operation that is the
 * response saved by the first run and `work` does not run. The stored value must
 * be JSON (use null for void). Callers map the stored value to their return
 * value, because a replay may need a different shape than the first run.
 */
export async function runClientOperation<T>(
  ctx: WriterCtx,
  userId: string,
  input: ClientOperationInput,
  work: () => Promise<T>,
): Promise<T> {
  if (!input.client_operation_id || !input.client_id) {
    fail("23514", "client operation identifiers are required");
  }

  const hash = await requestHash(input.request);
  const existing = await ctx.db
    .query("client_operations")
    .withIndex("by_user_id_client_operation_id", (q) =>
      q.eq("user_id", userId).eq("client_operation_id", input.client_operation_id),
    )
    .unique();

  if (existing) {
    if (existing.request_hash !== hash) {
      fail("23505", "client operation replay hash mismatch");
    }
    if (existing.status === "succeeded") {
      return (existing.stored_response ?? null) as T;
    }
    fail("55P03", "client operation is already in progress");
  }

  await assertNoPendingAccountDeletion(ctx, userId);
  assertClientOperationChecks(input);

  const now = nowIso();
  const rowId = await ctx.db.insert("client_operations", {
    id: newUuid(),
    user_id: userId,
    client_operation_id: input.client_operation_id,
    client_id: input.client_id,
    client_sequence: input.client_sequence,
    local_created_at: input.local_created_at,
    operation_kind: input.operation_kind,
    idempotency_scope: input.idempotency_scope,
    request_hash: hash,
    status: "started",
    attempt_count: 1,
    last_attempt_at: now,
    created_at: now,
    updated_at: now,
  });

  const result = await work();
  const stored = (result === undefined ? null : result) as unknown;
  const completedAt = nowIso();
  await ctx.db.patch(rowId, {
    status: "succeeded",
    completed_at: completedAt,
    stored_response: stored,
    response_hash: await sha256Hex(stableStringify(stored ?? {})),
    updated_at: completedAt,
  });
  return result;
}

function assertClientOperationChecks(input: ClientOperationInput): void {
  if (!(input.client_sequence > 0)) {
    checkViolation("client_operations", "client_operations_client_sequence_check");
  }
  if (input.operation_kind.length < 1 || input.operation_kind.length > 120) {
    checkViolation("client_operations", "client_operations_operation_kind_check");
  }
  if (input.idempotency_scope.length < 1 || input.idempotency_scope.length > 160) {
    checkViolation("client_operations", "client_operations_idempotency_scope_check");
  }
}
