import { v, type ObjectType } from "convex/values";
import { mutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { requireUserId } from "./lib/auth";
import { runClientOperation } from "./lib/clientOperations";
import { fail } from "./lib/errors";
import { newUuid, optionalTimestampArg, optionalUuidArg, uuidArg } from "./lib/ids";
import { consumeRateLimit } from "./lib/rateLimits";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { addPairSafetyWarningFlag, blockRelationship } from "./lib/relationshipBlock";
import {
  canReportRelationshipContent,
  enqueueReportSnapshotAssets,
  resolveContentReportTarget,
} from "./lib/reportTargets";
import { nowIso } from "./lib/time";

const REASONS = [
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
] as const;
type Reason = (typeof REASONS)[number];

const reportArgs = {
  p_reason: v.string(),
  p_note: v.optional(v.union(v.null(), v.string())),
  p_target_kind: v.string(),
  p_target_id: v.string(),
  p_target_aux_id: v.optional(v.union(v.null(), v.string())),
  p_block_reported_user: v.optional(v.union(v.null(), v.boolean())),
  p_client_operation_id: v.string(),
  p_client_id: v.string(),
  p_client_sequence: v.number(),
  p_local_created_at: v.string(),
};

type ReportArgs = ObjectType<typeof reportArgs>;

/** Port of `internal.submit_content_report`. Returns the report id. */
async function submitContentReport(ctx: MutationCtx, args: ReportArgs, leaveRelationship: boolean): Promise<string> {
  const userId = await requireUserId(ctx);
  const reason = args.p_reason.trim().toLowerCase();
  const targetKind = args.p_target_kind.trim().toLowerCase();
  const note = (args.p_note ?? "").trim() || undefined;
  if (!(REASONS as readonly string[]).includes(reason)) {
    fail("23514", "report reason is not supported");
  }
  if (note !== undefined && Array.from(note).length > 4000) {
    fail("23514", "report note is too long");
  }
  const targetId = uuidArg(args.p_target_id);
  const targetAuxId = optionalUuidArg(args.p_target_aux_id);
  const blockReportedUser = args.p_block_reported_user ?? false;

  const stored = await runClientOperation(
    ctx,
    userId,
    {
      client_operation_id: uuidArg(args.p_client_operation_id),
      client_id: uuidArg(args.p_client_id),
      client_sequence: args.p_client_sequence,
      local_created_at: optionalTimestampArg(args.p_local_created_at)!,
      operation_kind: "submit_content_report",
      idempotency_scope: "reports",
      request: {
        kind: "submit_content_report",
        reason,
        note: note ?? "",
        target_kind: targetKind,
        target_id: targetId,
        target_aux_id: targetAuxId ?? "",
        leave_relationship: leaveRelationship,
        block_reported_user: blockReportedUser,
      },
    },
    async () => {
      await consumeRateLimit(ctx, "contentReport", userId);
      const target = await resolveContentReportTarget(ctx, userId, targetKind, targetId, targetAuxId);
      if (!target) {
        return fail("22023", "report target was not found");
      }
      if (target.reported_user_id === userId) {
        fail("23514", "users cannot report themselves");
      }
      if (!(await canReportRelationshipContent(ctx, target.couple_id, userId))) {
        fail("42501", "report target is not connected to a reportable relationship");
      }

      const now = nowIso();
      const reportId = newUuid();
      await ctx.db.insert("content_reports", {
        id: reportId,
        reporter_user_id: userId,
        reported_user_id: target.reported_user_id,
        couple_id: target.couple_id,
        pair_id: target.pair_id,
        reason: reason as Reason,
        note,
        status: "submitted",
        block_requested: blockReportedUser,
        leave_requested: leaveRelationship,
        created_at: now,
        updated_at: now,
      });
      const ifKind = <T>(kind: string, value: T) => (targetKind === kind ? value : undefined);
      await ctx.db.insert("content_report_targets", {
        report_id: reportId,
        target_kind: targetKind as "daily_answer",
        daily_answer_id: ifKind("daily_answer", targetId),
        memory_id: ifKind("memory", targetId),
        memory_note_id: ifKind("memory_note", targetId),
        memory_media_id: ifKind("memory_media", targetId),
        message_id: ifKind("thread_message", targetId),
        message_media_message_id: ifKind("thread_message_media", targetId),
        message_media_asset_id: ifKind("thread_message_media", targetAuxId),
        widget_drawing_revision_id: ifKind("widget_drawing_revision", targetId),
        media_asset_id: ifKind("media_asset", targetId),
        profile_user_id: ifKind("profile", targetId),
        conduct_user_id: ifKind("conduct", targetId),
        created_at: now,
      });
      await ctx.db.insert("report_snapshots", {
        report_id: reportId,
        snapshot: {
          schema_version: 1,
          report_id: reportId,
          target: target.snapshot,
          reporter_user_id: userId,
          reported_user_id: target.reported_user_id,
          couple_id: target.couple_id,
          pair_id: target.pair_id,
          reason,
          note: note ?? null,
          created_at: now,
        },
        created_at: now,
      });
      await enqueueReportSnapshotAssets(ctx, reportId, target.snapshot);
      await addPairSafetyWarningFlag(ctx, target.pair_id, reportId);

      if (blockReportedUser) {
        await blockRelationship(ctx, userId, target.reported_user_id, reportId);
      } else if (leaveRelationship) {
        await endRelationshipForPair(ctx, target.pair_id, userId, "reported");
      }
      return { report_id: reportId };
    },
  );
  return stored.report_id;
}

/** Port of the public `submit_leave_and_report` wrapper. */
export const submit_leave_and_report = mutation({
  args: reportArgs,
  handler: (ctx, args) => submitContentReport(ctx, args, true),
});
