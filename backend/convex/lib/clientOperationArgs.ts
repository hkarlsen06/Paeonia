import { v } from "convex/values";
import type { ClientOperationInput } from "./clientOperations";
import { timestampArg, uuidArg } from "./ids";

/** The four local-first arguments every client-operation RPC accepts. */
export const clientOperationArgs = {
  p_client_operation_id: v.string(),
  p_client_id: v.string(),
  p_client_sequence: v.number(),
  p_local_created_at: v.string(),
};

type ClientOperationArgs = {
  p_client_operation_id: string;
  p_client_id: string;
  p_client_sequence: number;
  p_local_created_at: string;
};

/** Normalizes the client-operation arguments and attaches the operation description. */
export function toClientOperation(
  args: ClientOperationArgs,
  operation: { kind: string; scope: string; request: unknown },
): ClientOperationInput {
  return {
    client_operation_id: uuidArg(args.p_client_operation_id),
    client_id: uuidArg(args.p_client_id),
    client_sequence: args.p_client_sequence,
    local_created_at: timestampArg(args.p_local_created_at),
    operation_kind: operation.kind,
    idempotency_scope: operation.scope,
    request: operation.request,
  };
}
