import { v } from "convex/values";
import type { Doc, Id, TableNames } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";
import { sha256Hex } from "./lib/crypto";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, withTouch, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { newUuid, optionalTimestampArg, uuidArg } from "./lib/ids";
import { addPairSafetyWarningFlag, upsertRelationshipBlock } from "./lib/relationshipBlock";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { snapshotDeleteAfter } from "./lib/reportTargets";
import { addMs, nowIso } from "./lib/time";

// ---- Operator moderation (run with `npx convex run moderation:<name>`) ----

const ACTIONS = [
  "hide",
  "remove",
  "restore",
  "reject_upload",
  "delete_storage",
  "create_pair_warning",
  "clear_pair_warning",
  "block_pair",
  "unblock_pair",
] as const;
type ActionKind = (typeof ACTIONS)[number];
const OPERATOR_KINDS = ["service_role", "sql_runbook", "edge_function", "admin_user"] as const;
type OperatorKind = (typeof OPERATOR_KINDS)[number];
type ModerationStatus = Doc<"profiles">["moderation_status"];

/** Port of `internal.infer_report_target_for_moderation`. Null when the report has no target row. */
export async function inferReportTarget(
  ctx: ReaderCtx,
  reportId: string,
): Promise<{ target_kind: string; target_id: string | null; target_aux_id: string | null } | null> {
  const target = await ctx.db
    .query("content_report_targets")
    .withIndex("by_report_id", (q) => q.eq("report_id", reportId))
    .first();
  if (!target) return null;
  return {
    target_kind: target.target_kind,
    target_id:
      target.daily_answer_id ??
      target.memory_id ??
      target.memory_note_id ??
      target.memory_media_id ??
      target.message_id ??
      target.message_media_message_id ??
      target.widget_drawing_revision_id ??
      target.media_asset_id ??
      target.profile_user_id ??
      target.conduct_user_id ??
      null,
    target_aux_id: target.message_media_asset_id ?? null,
  };
}

export const infer_report_target_for_moderation = internalQuery({
  args: { p_report_id: v.string() },
  handler: async (ctx, args) => {
    const target = await inferReportTarget(ctx, uuidArg(args.p_report_id));
    return target ? [target] : [];
  },
});

/** What `apply_report_moderation_action` needs to know about one moderated row. */
type LoadedTarget = {
  previousStatus: ModerationStatus;
  moderationReportId: string | undefined;
  /** Assets that block a restore while queued for deletion. */
  restoreAssetIds: string[];
  restoreMessage: string;
  /** Assets queued for deletion by `remove` and `delete_storage`. */
  storageAssetIds: string[];
  setStatus: (status: ModerationStatus, reportId: string | undefined) => Promise<void>;
};

const CONTENT_RESTORE_MESSAGE = "cannot restore content with media queued for storage deletion";
const MEDIA_RESTORE_MESSAGE = "cannot restore media queued for storage deletion";

function notFound(): never {
  return fail("22023", "moderation target was not found");
}

async function loadTarget(
  ctx: WriterCtx,
  kind: string,
  targetId: string | null,
  auxId: string | null,
  action: ActionKind,
): Promise<LoadedTarget> {
  const moderationPatch = (status: ModerationStatus, reportId: string | undefined) => ({
    moderation_status: status,
    moderated_at: nowIso(),
    moderation_report_id: reportId,
  });
  // The tables differ in their update trigger: set_updated_at or touch_updated_at_and_revision.
  const simple = <T extends TableNames>(row: Doc<T> & { moderation_status: ModerationStatus; moderation_report_id?: string }) =>
    ({
      previousStatus: row.moderation_status,
      moderationReportId: row.moderation_report_id,
      setStatus: async (status: ModerationStatus, reportId: string | undefined) => {
        await ctx.db.patch(row._id as Id<T>, withUpdatedAt(moderationPatch(status, reportId)) as never);
      },
    }) satisfies Partial<LoadedTarget>;
  const touched = <T extends TableNames>(
    row: Doc<T> & { moderation_status: ModerationStatus; moderation_report_id?: string; revision: number },
  ) =>
    ({
      previousStatus: row.moderation_status,
      moderationReportId: row.moderation_report_id,
      setStatus: async (status: ModerationStatus, reportId: string | undefined) => {
        await ctx.db.patch(row._id as Id<T>, withTouch(row, moderationPatch(status, reportId)) as never);
      },
    }) satisfies Partial<LoadedTarget>;
  const assetIdsOf = async (table: "daily_answer_media" | "memory_media" | "thread_message_media", id: string) => {
    if (table === "daily_answer_media") {
      return (await ctx.db.query(table).withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", id)).collect()).map(
        (row) => row.media_asset_id,
      );
    }
    if (table === "memory_media") {
      return (await ctx.db.query(table).withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", id)).collect()).map(
        (row) => row.media_asset_id,
      );
    }
    return (await ctx.db.query(table).withIndex("by_message_id_sort_order", (q) => q.eq("message_id", id)).collect()).map(
      (row) => row.media_asset_id,
    );
  };

  switch (kind) {
    case "daily_answer": {
      const row = await getByUuid(ctx, "daily_question_answers", targetId);
      if (!row) return notFound();
      const assets = await assetIdsOf("daily_answer_media", row.id);
      return { ...simple(row), restoreAssetIds: assets, restoreMessage: CONTENT_RESTORE_MESSAGE, storageAssetIds: assets };
    }
    case "memory": {
      const row = await getByUuid(ctx, "memories", targetId);
      if (!row) return notFound();
      const assets = await assetIdsOf("memory_media", row.id);
      return { ...touched(row), restoreAssetIds: assets, restoreMessage: CONTENT_RESTORE_MESSAGE, storageAssetIds: assets };
    }
    case "memory_note": {
      const row = await getByUuid(ctx, "memory_notes", targetId);
      if (!row) return notFound();
      return { ...touched(row), restoreAssetIds: [], restoreMessage: CONTENT_RESTORE_MESSAGE, storageAssetIds: [] };
    }
    case "memory_media": {
      const row = await getByUuid(ctx, "memory_media", targetId);
      if (!row || !(await getByUuid(ctx, "media_assets", row.media_asset_id))) return notFound();
      return {
        ...simple(row),
        restoreAssetIds: [row.media_asset_id],
        restoreMessage: MEDIA_RESTORE_MESSAGE,
        storageAssetIds: [row.media_asset_id],
      };
    }
    case "thread_message": {
      const row = await getByUuid(ctx, "thread_messages", targetId);
      if (!row) return notFound();
      const assets = await assetIdsOf("thread_message_media", row.id);
      return { ...simple(row), restoreAssetIds: assets, restoreMessage: CONTENT_RESTORE_MESSAGE, storageAssetIds: assets };
    }
    case "thread_message_media": {
      // The moderation state lives on the media asset itself.
      const row = await getByUuid(ctx, "media_assets", auxId);
      if (!row) return notFound();
      return { ...simple(row), restoreAssetIds: [row.id], restoreMessage: MEDIA_RESTORE_MESSAGE, storageAssetIds: [row.id] };
    }
    case "widget_drawing_revision": {
      const row = await getByUuid(ctx, "widget_drawing_revisions", targetId);
      if (!row || !(await getByUuid(ctx, "media_assets", row.payload_media_asset_id))) return notFound();
      return {
        ...simple(row),
        restoreAssetIds: [row.payload_media_asset_id],
        restoreMessage: MEDIA_RESTORE_MESSAGE,
        storageAssetIds: [row.payload_media_asset_id],
      };
    }
    case "media_asset": {
      const row = await getByUuid(ctx, "media_assets", targetId);
      if (!row) return notFound();
      return { ...simple(row), restoreAssetIds: [row.id], restoreMessage: MEDIA_RESTORE_MESSAGE, storageAssetIds: [row.id] };
    }
    case "profile": {
      const row = targetId
        ? await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", targetId)).unique()
        : null;
      if (!row) return notFound();
      const photo = row.profile_photo_asset_id ? [row.profile_photo_asset_id] : [];
      return {
        ...touched(row),
        restoreAssetIds: photo,
        restoreMessage: CONTENT_RESTORE_MESSAGE,
        // Only an explicit delete_storage removes a profile photo.
        storageAssetIds: action === "delete_storage" ? photo : [],
      };
    }
    default:
      return fail("23514", "moderation action cannot change this target kind");
  }
}

/** Port of `internal.apply_report_moderation_action`. Returns the moderation action id. */
export const apply_report_moderation_action = internalMutation({
  args: {
    p_report_id: v.string(),
    p_action_kind: v.string(),
    p_operator_kind: v.string(),
    p_operator_identifier: v.string(),
    p_reason: v.optional(v.union(v.null(), v.string())),
    p_notes: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const report = await getByUuid(ctx, "content_reports", uuidArg(args.p_report_id));
    if (!report) {
      return fail("22023", "content report was not found");
    }
    const target = await inferReportTarget(ctx, report.id);
    if (!target) {
      return fail("22023", "content report target was not found");
    }

    const action = args.p_action_kind.trim().toLowerCase();
    const operatorKind = args.p_operator_kind.trim().toLowerCase();
    const operatorIdentifier = args.p_operator_identifier.trim() || undefined;
    if (!(ACTIONS as readonly string[]).includes(action)) {
      fail("23514", "moderation action is not supported");
    }
    if (!(OPERATOR_KINDS as readonly string[]).includes(operatorKind) || operatorIdentifier === undefined) {
      fail("23514", "moderation operator metadata is required");
    }
    const actionKind = action as ActionKind;

    const newStatus: ModerationStatus | undefined = (
      {
        hide: "hidden",
        remove: "removed",
        delete_storage: "removed",
        restore: "visible",
        reject_upload: "rejected",
      } as Partial<Record<ActionKind, ModerationStatus>>
    )[actionKind];

    let previousStatus: ModerationStatus | undefined;
    let storageAction: "none" | "queued_delete" | undefined;

    if (newStatus !== undefined) {
      const loaded = await loadTarget(ctx, target.target_kind, target.target_id, target.target_aux_id, actionKind);
      previousStatus = loaded.previousStatus;
      const restore = actionKind === "restore";
      if (restore) {
        if (loaded.moderationReportId !== report.id) {
          fail("23514", "cannot restore content moderated by a different report");
        }
        for (const assetId of loaded.restoreAssetIds) {
          const asset = await getByUuid(ctx, "media_assets", assetId);
          if (asset && (asset.deleted_at !== undefined || asset.storage_delete_status !== "none")) {
            fail("23514", loaded.restoreMessage);
          }
        }
      }
      await loaded.setStatus(newStatus, restore ? undefined : report.id);

      storageAction = "none";
      if (actionKind === "remove" || actionKind === "delete_storage") {
        let queued = 0;
        for (const assetId of loaded.storageAssetIds) {
          const asset = await getByUuid(ctx, "media_assets", assetId);
          if (!asset) continue;
          await ctx.db.patch(
            asset._id,
            withUpdatedAt({
              deleted_at: asset.deleted_at ?? nowIso(),
              storage_delete_status: asset.storage_delete_status === "deleted" ? ("deleted" as const) : ("pending" as const),
              last_storage_delete_error: undefined,
            }),
          );
          queued += 1;
        }
        if (queued > 0) {
          storageAction = "queued_delete";
        } else if (actionKind === "delete_storage") {
          fail("23514", "delete_storage found no storage assets for this target");
        }
      }
    } else if (actionKind === "create_pair_warning") {
      await addPairSafetyWarningFlag(ctx, report.pair_id, report.id);
    } else if (actionKind === "clear_pair_warning") {
      const flags = await ctx.db
        .query("pair_safety_warning_flags")
        .withIndex("by_pair_id_source_report_id", (q) => q.eq("pair_id", report.pair_id).eq("source_report_id", report.id))
        .collect();
      for (const flag of flags) await ctx.db.delete(flag._id);
    } else if (actionKind === "block_pair") {
      await upsertRelationshipBlock(ctx, report.pair_id, report.reporter_user_id, report.reported_user_id, report.id);
      await endRelationshipForPair(ctx, report.pair_id, report.reporter_user_id, "moderation_block");
    } else if (actionKind === "unblock_pair") {
      const blocks = await ctx.db
        .query("relationship_blocks")
        .withIndex("by_pair_id_revoked_at", (q) => q.eq("pair_id", report.pair_id).eq("revoked_at", undefined))
        .collect();
      for (const block of blocks) {
        await ctx.db.patch(block._id, {
          revoked_at: nowIso(),
          revoked_by_user_id: block.blocked_by_user_id,
          revoke_reason: "admin_correction",
        });
      }
    }

    const now = nowIso();
    const actionId = newUuid();
    await ctx.db.insert("moderation_actions", {
      id: actionId,
      report_id: report.id,
      action_kind: actionKind,
      status: "applied",
      target_kind: target.target_kind,
      target_id: target.target_id ?? undefined,
      previous_moderation_status: previousStatus,
      new_moderation_status: newStatus,
      storage_action: storageAction,
      operator_kind: operatorKind as OperatorKind,
      operator_identifier: operatorIdentifier,
      reason: args.p_reason ?? undefined,
      notes: args.p_notes ?? undefined,
      created_at: now,
      updated_at: now,
    });

    await ctx.db.patch(
      report._id,
      withUpdatedAt({
        status: actionKind === "restore" ? ("closed" as const) : ("action_taken" as const),
        resolved_at: report.resolved_at ?? now,
      }),
    );

    // The first moderation action starts the snapshot retention clock.
    const deleteAfter = snapshotDeleteAfter(now);
    const snapshot = await ctx.db
      .query("report_snapshots")
      .withIndex("by_report_id", (q) => q.eq("report_id", report.id))
      .unique();
    if (snapshot && snapshot.delete_after === undefined) {
      await ctx.db.patch(snapshot._id, { delete_after: deleteAfter });
    }
    const snapshotAssets = await ctx.db
      .query("report_snapshot_assets")
      .withIndex("by_report_id", (q) => q.eq("report_id", report.id))
      .collect();
    for (const asset of snapshotAssets) {
      if (asset.delete_after === undefined) {
        await ctx.db.patch(asset._id, withUpdatedAt({ delete_after: deleteAfter }));
      }
    }
    return actionId;
  },
});

// ---- Report snapshot asset pipeline ----

const COPY_RETRY_MS = 15 * 60_000;
const DEFAULT_MAX_ATTEMPTS = 5;

function checkClaimWindow(limit: number, maxAttempts: number): void {
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    fail("23514", "report snapshot copy claim limit is out of range");
  }
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 25) {
    fail("23514", "report snapshot copy max attempts is out of range");
  }
}

type ClaimedCopy = {
  snapshot_asset_id: string;
  report_id: string;
  source_bucket: string;
  source_storage_path: string;
  destination_bucket: string;
  destination_storage_path: string;
  copy_attempts: number;
  source_storage_id: string | null;
  byte_size: number | null;
  sha256: string | null;
};

/** Port of `internal.claim_report_snapshot_asset_copies`. Adds `source_storage_id` for the copy action. */
export const claim_report_snapshot_asset_copies = internalMutation({
  args: {
    p_now: v.optional(v.string()),
    p_limit: v.optional(v.number()),
    p_retry_after_ms: v.optional(v.number()),
    p_max_attempts: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = args.p_limit ?? 100;
    const maxAttempts = args.p_max_attempts ?? DEFAULT_MAX_ATTEMPTS;
    checkClaimWindow(limit, maxAttempts);
    const staleBefore = addMs(now, -(args.p_retry_after_ms ?? COPY_RETRY_MS));

    const candidates: Doc<"report_snapshot_assets">[] = [];
    for (const status of ["pending_copy", "copying"] as const) {
      const rows = await ctx.db
        .query("report_snapshot_assets")
        .withIndex("by_copy_status_copy_attempts_copy_claimed_at_created_at", (q) =>
          q.eq("copy_status", status).lt("copy_attempts", maxAttempts),
        )
        .collect();
      candidates.push(
        ...rows.filter(
          (row) =>
            (row.delete_after === undefined || row.delete_after > now) &&
            (status === "pending_copy" || (row.copy_claimed_at !== undefined && row.copy_claimed_at <= staleBefore)),
        ),
      );
    }
    candidates.sort((a, b) => (a.created_at !== b.created_at ? (a.created_at < b.created_at ? -1 : 1) : a.id < b.id ? -1 : 1));

    const claimed = [];
    for (const asset of candidates.slice(0, limit)) {
      await ctx.db.patch(
        asset._id,
        withUpdatedAt({
          copy_status: "copying" as const,
          copy_claimed_at: now,
          copy_attempts: asset.copy_attempts + 1,
          last_copy_error: undefined,
        }),
      );
      const source = await ctx.db
        .query("media_assets")
        .withIndex("by_bucket_storage_path", (q) =>
          q.eq("bucket", asset.source_bucket).eq("storage_path", asset.source_storage_path),
        )
        .unique();
      claimed.push({
        snapshot_asset_id: asset.id,
        report_id: asset.report_id,
        source_bucket: asset.source_bucket,
        source_storage_path: asset.source_storage_path,
        destination_bucket: asset.bucket,
        destination_storage_path: asset.storage_path,
        copy_attempts: asset.copy_attempts + 1,
        source_storage_id: source?.storage_id ?? null,
        byte_size: asset.byte_size ?? null,
        sha256: asset.sha256 ?? null,
      });
    }
    return claimed;
  },
});

/** Port of `internal.mark_report_snapshot_asset_copied`, plus the stored blob id. */
export const mark_report_snapshot_asset_copied = internalMutation({
  args: { p_snapshot_asset_id: v.string(), p_storage_id: v.optional(v.id("_storage")) },
  handler: async (ctx, args) => {
    const asset = await getByUuid(ctx, "report_snapshot_assets", uuidArg(args.p_snapshot_asset_id));
    if (!asset) return false;
    if (
      ["pending_copy", "copying", "copy_failed"].includes(asset.copy_status) &&
      asset.byte_size !== undefined &&
      asset.sha256 !== undefined
    ) {
      await ctx.db.patch(
        asset._id,
        withUpdatedAt({
          copy_status: "copied" as const,
          copy_completed_at: asset.copy_completed_at ?? nowIso(),
          last_copy_error: undefined,
          storage_delete_status: "none" as const,
          storage_deleted_at: undefined,
          last_storage_delete_error: undefined,
          storage_id: args.p_storage_id,
        }),
      );
      return true;
    }
    return asset.copy_status === "copied";
  },
});

/** Port of `internal.mark_report_snapshot_asset_copy_failed`. */
export const mark_report_snapshot_asset_copy_failed = internalMutation({
  args: { p_snapshot_asset_id: v.string(), p_error: v.optional(v.union(v.null(), v.string())), p_terminal: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    const asset = await getByUuid(ctx, "report_snapshot_assets", uuidArg(args.p_snapshot_asset_id));
    if (!asset || !["pending_copy", "copying", "copy_failed"].includes(asset.copy_status)) return false;
    await ctx.db.patch(
      asset._id,
      withUpdatedAt({
        copy_status: args.p_terminal ? ("copy_failed" as const) : ("pending_copy" as const),
        last_copy_error: Array.from((args.p_error ?? "").trim()).slice(0, 4000).join("") || undefined,
      }),
    );
    return true;
  },
});

/**
 * Replaces the Edge Function copy step: reads each claimed source blob from
 * Convex storage, checks its size and checksum, and stores a second copy.
 */
export const copy_report_snapshot_assets = internalAction({
  args: { p_limit: v.optional(v.number()), p_max_attempts: v.optional(v.number()) },
  handler: async (ctx, args): Promise<{ claimed: number; copied: number; failed: number }> => {
    const maxAttempts = args.p_max_attempts ?? DEFAULT_MAX_ATTEMPTS;
    const claimed: ClaimedCopy[] = await ctx.runMutation(internal.moderation.claim_report_snapshot_asset_copies, {
      p_limit: args.p_limit,
      p_max_attempts: maxAttempts,
    });
    let copied = 0;
    let failed = 0;
    for (const asset of claimed) {
      try {
        if (!asset.source_storage_id) throw new Error("source file is missing");
        const blob = await ctx.storage.get(asset.source_storage_id as Id<"_storage">);
        if (!blob) throw new Error("source file is missing");
        if (asset.byte_size !== null && blob.size !== asset.byte_size) throw new Error("source file size changed");
        if (asset.sha256 !== null && (await sha256Hex(new Uint8Array(await blob.arrayBuffer()))) !== asset.sha256) {
          throw new Error("source file checksum changed");
        }
        const storageId = await ctx.storage.store(blob);
        await ctx.runMutation(internal.moderation.mark_report_snapshot_asset_copied, {
          p_snapshot_asset_id: asset.snapshot_asset_id,
          p_storage_id: storageId,
        });
        copied += 1;
      } catch (error) {
        failed += 1;
        await ctx.runMutation(internal.moderation.mark_report_snapshot_asset_copy_failed, {
          p_snapshot_asset_id: asset.snapshot_asset_id,
          p_error: error instanceof Error ? error.message : String(error),
          p_terminal: asset.copy_attempts >= maxAttempts,
        });
      }
    }
    return { claimed: claimed.length, copied, failed };
  },
});

/**
 * Collapses `claim_report_snapshot_storage_deletes`,
 * `mark_report_snapshot_storage_deleted` and `..._delete_failed`. Convex deletes
 * the blob inside the mutation, so claim, delete, and mark share one transaction.
 */
export const delete_expired_report_snapshot_storage = internalMutation({
  args: { p_now: v.optional(v.string()), p_limit: v.optional(v.number()), p_max_attempts: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = args.p_limit ?? 100;
    const maxAttempts = args.p_max_attempts ?? DEFAULT_MAX_ATTEMPTS;
    checkClaimWindow(limit, maxAttempts);
    const retryBefore = addMs(now, -COPY_RETRY_MS);

    const due: Doc<"report_snapshot_assets">[] = [];
    for (const status of ["none", "pending", "retrying"] as const) {
      const rows = await ctx.db
        .query("report_snapshot_assets")
        .withIndex("by_storage_delete_status_storage_delete_attempts_updated_at", (q) =>
          q.eq("storage_delete_status", status).lt("storage_delete_attempts", maxAttempts),
        )
        .collect();
      due.push(
        ...rows.filter(
          (row) =>
            row.delete_after !== undefined &&
            row.delete_after <= now &&
            row.copy_status === "copied" &&
            (status !== "retrying" || row.updated_at <= retryBefore),
        ),
      );
    }
    due.sort((a, b) =>
      a.delete_after! !== b.delete_after! ? (a.delete_after! < b.delete_after! ? -1 : 1) : a.id < b.id ? -1 : 1,
    );

    let deleted = 0;
    let failed = 0;
    for (const asset of due.slice(0, limit)) {
      const attempts = asset.storage_delete_attempts + 1;
      try {
        if (asset.storage_id) await ctx.storage.delete(asset.storage_id);
        await ctx.db.patch(
          asset._id,
          withUpdatedAt({
            storage_delete_status: "deleted" as const,
            storage_delete_attempts: attempts,
            storage_deleted_at: now,
            last_storage_delete_error: undefined,
            storage_id: undefined,
          }),
        );
        deleted += 1;
      } catch (error) {
        failed += 1;
        await ctx.db.patch(
          asset._id,
          withUpdatedAt({
            storage_delete_status: attempts >= maxAttempts ? ("failed" as const) : ("retrying" as const),
            storage_delete_attempts: attempts,
            last_storage_delete_error: (error instanceof Error ? error.message : String(error)).slice(0, 4000),
          }),
        );
      }
    }
    return { claimed: deleted + failed, deleted, failed };
  },
});

/** Port of `internal.purge_deleted_report_snapshots`. */
export const purge_deleted_report_snapshots = internalMutation({
  args: { p_now: v.optional(v.string()), p_limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = args.p_limit ?? 100;
    if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
      fail("23514", "report snapshot purge limit is out of range");
    }

    const assets = await ctx.db
      .query("report_snapshot_assets")
      .withIndex("by_delete_after_storage_delete_status", (q) => q.gt("delete_after", undefined).lte("delete_after", now))
      .collect();
    const purgeable = assets
      .filter(
        (asset) =>
          (asset.copy_status === "copied" && asset.storage_delete_status === "deleted") ||
          asset.copy_status === "pending_copy" ||
          asset.copy_status === "copy_failed",
      )
      .sort((a, b) => (a.delete_after! !== b.delete_after! ? (a.delete_after! < b.delete_after! ? -1 : 1) : a.id < b.id ? -1 : 1))
      .slice(0, limit);
    for (const asset of purgeable) await ctx.db.delete(asset._id);

    const snapshots = await ctx.db
      .query("report_snapshots")
      .withIndex("by_delete_after", (q) => q.gt("delete_after", undefined).lte("delete_after", now))
      .collect();
    let snapshotsDeleted = 0;
    for (const snapshot of snapshots.sort((a, b) => (a.delete_after! < b.delete_after! ? -1 : 1))) {
      if (snapshotsDeleted >= limit) break;
      const remaining = await ctx.db
        .query("report_snapshot_assets")
        .withIndex("by_report_id", (q) => q.eq("report_id", snapshot.report_id))
        .first();
      if (remaining) continue;
      await ctx.db.delete(snapshot._id);
      snapshotsDeleted += 1;
    }
    return { snapshot_asset_rows_deleted: purgeable.length, snapshot_rows_deleted: snapshotsDeleted };
  },
});

/** Cron entry point: delete expired snapshot blobs, then purge the finished rows. */
export const cleanup_report_snapshots = internalMutation({
  args: {},
  handler: async (ctx): Promise<{ storage: unknown; purged: unknown }> => {
    const storage: unknown = await ctx.runMutation(internal.moderation.delete_expired_report_snapshot_storage, {});
    const purged: unknown = await ctx.runMutation(internal.moderation.purge_deleted_report_snapshots, {});
    return { storage, purged };
  },
});
