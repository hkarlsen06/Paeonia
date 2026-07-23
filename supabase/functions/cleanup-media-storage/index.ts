/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// Drains media storage delete queues through the Supabase Storage API.
// Safe to call repeatedly because rows are claimed atomically in Postgres.

import { type SupabaseContext, withSupabase } from "npm:@supabase/server@1.4.1";
import { drainRequestIsAuthorized } from "../_shared/drainAuth.ts";

interface ClaimedMediaDelete {
  media_asset_id: string;
  bucket: string;
  storage_path: string;
  storage_delete_attempts: number;
}

interface ClaimedReportSnapshotDelete {
  snapshot_asset_id: string;
  report_id: string;
  bucket: string;
  storage_path: string;
  storage_delete_attempts: number;
}

interface DrainStats {
  claimed: number;
  deleted: number;
  failed: number;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function positiveIntParam(
  request: Request,
  name: string,
  fallback: number,
  max: number,
): number {
  const raw = new URL(request.url).searchParams.get(name);
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > max) return fallback;
  return parsed;
}

// Supabase Storage deletes are the only path that removes bytes from the bucket.
async function removeStorageObject(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  bucket: string,
  storagePath: string,
): Promise<void> {
  const { error } = await supabase.storage.from(bucket).remove([storagePath]);
  if (error) throw new Error(error.message);
}

async function drainMediaDeletes(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  limit: number,
  maxAttempts: number,
): Promise<DrainStats> {
  const { data, error } = await supabase.rpc("claim_media_storage_deletes", {
    p_limit: limit,
    p_max_attempts: maxAttempts,
  });
  if (error) throw new Error(error.message);

  const batch = (data ?? []) as ClaimedMediaDelete[];
  let deleted = 0;
  let failed = 0;

  for (const asset of batch) {
    try {
      await removeStorageObject(supabase, asset.bucket, asset.storage_path);
      const { error: markError } = await supabase.rpc(
        "mark_media_storage_deleted",
        { p_media_asset_id: asset.media_asset_id },
      );
      if (markError) throw new Error(markError.message);
      deleted++;
    } catch (error) {
      failed++;
      const terminal = asset.storage_delete_attempts >= maxAttempts;
      const { error: markError } = await supabase.rpc(
        "mark_media_storage_delete_failed",
        {
          p_media_asset_id: asset.media_asset_id,
          p_error: errorMessage(error),
          p_terminal: terminal,
        },
      );
      if (markError) {
        console.error("Unable to record media storage delete failure", {
          media_asset_id: asset.media_asset_id,
          error: markError.message,
        });
      }
    }
  }

  return { claimed: batch.length, deleted, failed };
}

async function drainReportSnapshotDeletes(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  limit: number,
  maxAttempts: number,
): Promise<DrainStats> {
  const { data, error } = await supabase.rpc(
    "claim_report_snapshot_storage_deletes",
    {
      p_limit: limit,
      p_max_attempts: maxAttempts,
    },
  );
  if (error) throw new Error(error.message);

  const batch = (data ?? []) as ClaimedReportSnapshotDelete[];
  let deleted = 0;
  let failed = 0;

  for (const asset of batch) {
    try {
      await removeStorageObject(supabase, asset.bucket, asset.storage_path);
      const { error: markError } = await supabase.rpc(
        "mark_report_snapshot_storage_deleted",
        { p_snapshot_asset_id: asset.snapshot_asset_id },
      );
      if (markError) throw new Error(markError.message);
      deleted++;
    } catch (error) {
      failed++;
      const terminal = asset.storage_delete_attempts >= maxAttempts;
      const { error: markError } = await supabase.rpc(
        "mark_report_snapshot_storage_delete_failed",
        {
          p_snapshot_asset_id: asset.snapshot_asset_id,
          p_error: errorMessage(error),
          p_terminal: terminal,
        },
      );
      if (markError) {
        console.error("Unable to record report snapshot delete failure", {
          snapshot_asset_id: asset.snapshot_asset_id,
          report_id: asset.report_id,
          error: markError.message,
        });
      }
    }
  }

  return { claimed: batch.length, deleted, failed };
}

Deno.serve(withSupabase({ auth: "none" }, handleRequest));

async function handleRequest(
  request: Request,
  context: SupabaseContext,
): Promise<Response> {
  if (request.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  if (!await drainRequestIsAuthorized(request)) {
    return new Response("unauthorized", { status: 401 });
  }

  const limit = positiveIntParam(request, "limit", 100, 500);
  const maxAttempts = positiveIntParam(request, "maxAttempts", 5, 25);
  const supabase = context.supabaseAdmin;

  try {
    const media = await drainMediaDeletes(supabase, limit, maxAttempts);
    const reportSnapshots = await drainReportSnapshotDeletes(
      supabase,
      limit,
      maxAttempts,
    );

    return new Response(
      JSON.stringify({
        claimed: media.claimed + reportSnapshots.claimed,
        deleted: media.deleted + reportSnapshots.deleted,
        failed: media.failed + reportSnapshots.failed,
        media,
        reportSnapshots,
      }),
      { headers: { "content-type": "application/json" } },
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: errorMessage(error) }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
}
