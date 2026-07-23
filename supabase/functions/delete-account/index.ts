/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// User calls atomically remove Paeonia data, optionally revoke Sign in with
// Apple, and revoke Supabase sessions. Trusted drain calls retry final Auth-user
// deletion. No provider credential or Supabase access token is persisted.

import { type SupabaseContext, withSupabase } from "npm:@supabase/server@1.4.1";
import {
  appleIdentitySubjects,
  revokeAppleAuthorization,
} from "../_shared/appleSignInDeletion.ts";
import { drainRequestIsAuthorized } from "../_shared/drainAuth.ts";

interface DeleteAccountBody {
  appleAuthorizationCode?: unknown;
}

interface AccountDeletionStart {
  id: string;
  deletion_job_id: string;
  auth_provider: "apple" | "google" | "unknown";
  provider_revocation_status: "not_required" | "succeeded" | "manual_required";
  auth_delete_status: string;
}

interface ClaimedAccountDeletion {
  job_id: string;
  request_id: string;
  user_id: string;
  auth_provider: string;
  provider_revocation_status: string;
  auth_delete_attempts: number;
}

interface ProcessResult {
  status: "completed" | "queued";
  errorCode?: string;
}

// Generated database types are not part of the Edge Function bundle yet.
// deno-lint-ignore no-explicit-any
type EdgeDatabase = any;
type AdminClient = SupabaseContext<EdgeDatabase>["supabaseAdmin"];

Deno.serve(
  withSupabase<EdgeDatabase>({ auth: ["user", "none"] }, handleRequest),
);

async function handleRequest(
  request: Request,
  context: SupabaseContext<EdgeDatabase>,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Method not allowed" });
  }

  if (context.authMode === "user") {
    return await handleUserDeletion(request, context);
  }

  if (!await drainRequestIsAuthorized(request)) {
    return jsonResponse(401, { ok: false, error: "Unauthorized" });
  }
  return await handleDrain(context.supabaseAdmin);
}

async function handleUserDeletion(
  request: Request,
  context: SupabaseContext<EdgeDatabase>,
): Promise<Response> {
  const userClient = context.supabase;
  const admin = context.supabaseAdmin;

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user?.id) {
    return jsonResponse(401, { ok: false, error: "Invalid session" });
  }

  const { data: startData, error: startError } = await userClient.rpc(
    "request_account_deletion",
  );
  if (startError) {
    console.error(
      "[delete-account] database deletion stage failed",
      startError.code,
    );
    return jsonResponse(500, {
      ok: false,
      error: "Could not start account deletion",
    });
  }

  const start = Array.isArray(startData)
    ? startData[0] as AccountDeletionStart | undefined
    : undefined;
  if (!start?.deletion_job_id) {
    return jsonResponse(500, {
      ok: false,
      error: "Could not start account deletion",
    });
  }

  // Reserve the Auth job before talking to Apple so the background drain cannot
  // delete the Auth identity out from under a fresh automatic revocation
  // attempt. A crashed reservation is reclaimed by the normal lease timeout.
  const claimedJob = await claimSpecificJob(admin, start.deletion_job_id);

  // Revoke every refresh token as early as possible. The local client also
  // signs out after this response, and hard Auth deletion removes sessions.
  const authHeader = request.headers.get("Authorization") ?? "";
  const { error: signOutError } = await admin.auth.admin.signOut(
    bearerToken(authHeader),
    "global",
  );
  if (signOutError) {
    console.warn(
      "[delete-account] global sign-out will be completed by Auth deletion",
    );
  }

  const body = await readBody(request);
  let revocationStatus = start.provider_revocation_status;
  let revocationErrorCode: string | null = null;

  if (start.auth_provider === "apple") {
    const result = await revokeAppleAuthorization(
      stringOrNull(body.appleAuthorizationCode),
      appleIdentitySubjects(userData.user),
    );
    revocationStatus = result.status;
    revocationErrorCode = result.status === "manual_required"
      ? result.errorCode
      : null;

    const { error } = await admin.rpc(
      "mark_account_deletion_provider_result",
      {
        p_job_id: start.deletion_job_id,
        p_status: revocationStatus,
        p_error_code: revocationErrorCode,
      },
    );
    if (error) {
      console.error(
        "[delete-account] provider result write failed",
        error.code,
      );
      revocationStatus = "manual_required";
      revocationErrorCode = "provider_result_not_recorded";
    }
  }

  // Manual Apple revocation is a provider boundary only. It must never keep the
  // Supabase account or any session alive.
  const authDeletion = claimedJob
    ? await deleteAuthUser(admin, claimedJob)
    : await processSpecificJob(admin, start.deletion_job_id);

  return jsonResponse(202, {
    ok: true,
    accepted: true,
    requestId: start.id,
    authDeleteStatus: authDeletion.status,
    appleRevocation: start.auth_provider === "apple"
      ? revocationStatus
      : "not_required",
    requiresManualAppleRevocation: start.auth_provider === "apple" &&
      revocationStatus === "manual_required",
    ...(revocationErrorCode ? { revocationErrorCode } : {}),
  });
}

async function handleDrain(admin: AdminClient): Promise<Response> {
  const { data, error } = await admin.rpc("claim_account_deletion_jobs", {
    p_now: new Date().toISOString(),
    p_limit: 25,
    p_retry_after: "5 minutes",
    p_max_attempts: 10,
    p_job_id: null,
  });
  if (error) {
    console.error("[delete-account] drain claim failed", error.code);
    return jsonResponse(500, {
      ok: false,
      error: "Could not process account deletions",
    });
  }

  const jobs = (data ?? []) as ClaimedAccountDeletion[];
  let completed = 0;
  let queued = 0;
  for (const job of jobs) {
    const result = await deleteAuthUser(admin, job);
    if (result.status === "completed") completed++;
    else queued++;
  }

  return jsonResponse(200, {
    ok: true,
    claimed: jobs.length,
    completed,
    queued,
  });
}

async function processSpecificJob(
  // deno-lint-ignore no-explicit-any
  admin: any,
  jobID: string,
): Promise<ProcessResult> {
  const { data, error } = await admin.rpc("claim_account_deletion_jobs", {
    p_now: new Date().toISOString(),
    p_limit: 1,
    p_retry_after: "5 minutes",
    p_max_attempts: 10,
    p_job_id: jobID,
  });
  if (error) {
    console.error("[delete-account] direct claim failed", error.code);
    return { status: "queued", errorCode: "job_claim_failed" };
  }

  const job = (data ?? [])[0] as ClaimedAccountDeletion | undefined;
  return job ? await deleteAuthUser(admin, job) : { status: "queued" };
}

async function claimSpecificJob(
  // deno-lint-ignore no-explicit-any
  admin: any,
  jobID: string,
): Promise<ClaimedAccountDeletion | null> {
  const { data, error } = await admin.rpc("claim_account_deletion_jobs", {
    p_now: new Date().toISOString(),
    p_limit: 1,
    p_retry_after: "5 minutes",
    p_max_attempts: 10,
    p_job_id: jobID,
  });
  if (error) {
    console.error("[delete-account] direct reservation failed", error.code);
    return null;
  }
  return (data ?? [])[0] as ClaimedAccountDeletion | undefined ?? null;
}

async function deleteAuthUser(
  // deno-lint-ignore no-explicit-any
  admin: any,
  job: ClaimedAccountDeletion,
): Promise<ProcessResult> {
  try {
    // Remove user-editable Auth metadata if the hard delete needs to retry.
    await admin.auth.admin.updateUserById(job.user_id, { user_metadata: {} });
    const { error } = await admin.auth.admin.deleteUser(job.user_id);
    if (error && error.status !== 404) {
      throw error;
    }

    const { error: markError } = await admin.rpc(
      "mark_account_deletion_completed",
      { p_job_id: job.job_id },
    );
    if (markError) throw markError;
    return { status: "completed" };
  } catch (error) {
    const errorCode = stableAuthDeleteErrorCode(error);
    console.error("[delete-account] Auth deletion queued", {
      job_id: job.job_id,
      error_code: errorCode,
    });
    const { error: markError } = await admin.rpc(
      "mark_account_deletion_auth_failed",
      {
        p_job_id: job.job_id,
        p_error_code: errorCode,
        p_max_attempts: 10,
      },
    );
    if (markError) {
      console.error("[delete-account] could not record retry", markError.code);
    }
    return { status: "queued", errorCode };
  }
}

async function readBody(request: Request): Promise<DeleteAccountBody> {
  try {
    const body = await request.json();
    return body && typeof body === "object" ? body as DeleteAccountBody : {};
  } catch {
    return {};
  }
}

function stringOrNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= 4096 ? trimmed : null;
}

function bearerToken(authorizationHeader: string): string {
  return authorizationHeader.replace(/^Bearer\s+/i, "").trim();
}

function stableAuthDeleteErrorCode(error: unknown): string {
  if (!error || typeof error !== "object") return "auth_delete_unexpected";
  const value = error as Record<string, unknown>;
  if (typeof value.code === "string") {
    return `auth_${sanitizeCode(value.code)}`;
  }
  if (typeof value.status === "number") return `auth_http_${value.status}`;
  return "auth_delete_unexpected";
}

function sanitizeCode(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_]+/g, "_").slice(0, 100);
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
