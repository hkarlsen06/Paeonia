"use node";

// APNs delivery. Node, because APNs only speaks HTTP/2. Claiming, result
// recording, and the pure request builders are in pushQueue.ts and lib/apns.ts.

import { connect, type ClientHttp2Session } from "node:http2";
import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import {
  apnsHeaders,
  apnsHost,
  cachedProviderTokens,
  errorMessage,
  readApnsConfig,
  sendWithEnvironmentFallback,
  type ApnsEnvironment,
  type ApnsHttpResponse,
  type ApnsSendRequest,
  type ApnsTransport,
} from "./lib/apns";
import { drainAppNotifications, drainWidgetPushes, type DrainStats } from "./lib/apnsDrain";

const REQUEST_TIMEOUT_MS = 20_000;

/** One HTTP/2 session per host for the life of a drain run. The JWT cache lives and dies with it. */
function createTransport(config: ReturnType<typeof readApnsConfig>): ApnsTransport & { close(): void } {
  const sessions = new Map<ApnsEnvironment, ClientHttp2Session>();

  const sessionFor = (environment: ApnsEnvironment): ClientHttp2Session => {
    const existing = sessions.get(environment);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const session = connect(`https://${apnsHost(environment)}`);
    // An idle session error must not crash the action. The next request opens a new session.
    session.on("error", () => sessions.delete(environment));
    session.on("close", () => sessions.delete(environment));
    sessions.set(environment, session);
    return session;
  };

  return {
    providerToken: cachedProviderTokens((environment) =>
      environment === "sandbox" ? config.sandbox : config.production,
    ),
    post(environment, jwt, request: ApnsSendRequest) {
      return new Promise<ApnsHttpResponse>((resolve, reject) => {
        const session = sessionFor(environment);
        const stream = session.request(apnsHeaders(jwt, request));
        let status = 0;
        let apnsId: string | undefined;
        let text = "";
        stream.setEncoding("utf8");
        stream.setTimeout(REQUEST_TIMEOUT_MS, () => stream.close());
        stream.on("response", (headers) => {
          status = Number(headers[":status"] ?? 0);
          const id = headers["apns-id"];
          apnsId = Array.isArray(id) ? id[0] : id;
        });
        stream.on("data", (chunk: string) => {
          text += chunk;
        });
        stream.on("error", reject);
        stream.on("close", () => {
          if (status === 0) {
            reject(new Error("APNs closed the connection without a response"));
            return;
          }
          let reason: string | undefined;
          try {
            const parsed = JSON.parse(text) as { reason?: unknown };
            if (parsed?.reason) reason = String(parsed.reason);
          } catch {
            // Keep the status based reason.
          }
          resolve({ status, apnsId, reason });
        });
        stream.end(request.body);
      });
    },
    close() {
      for (const session of sessions.values()) session.close();
      sessions.clear();
    },
  };
}

type DrainOutcome = { configured: boolean; app: DrainStats | null; widget: DrainStats | null };

async function drain(
  ctx: Parameters<typeof drainAppNotifications>[0],
  which: { app: boolean; widget: boolean },
): Promise<DrainOutcome> {
  const config = readApnsConfig(process.env);
  if (config.missing.length > 0) {
    console.error("push delivery is not configured", { missing: config.missing });
    return { configured: false, app: null, widget: null };
  }
  const transport = createTransport(config);
  const send = (request: ApnsSendRequest) => sendWithEnvironmentFallback(request, transport);
  try {
    const app = which.app ? await drainAppNotifications(ctx, send, config.bundleId) : null;
    const widget = which.widget ? await drainWidgetPushes(ctx, send, config.bundleId) : null;
    return { configured: true, app, widget };
  } catch (error) {
    console.error("push drain failed", { error: errorMessage(error) });
    throw error;
  } finally {
    transport.close();
  }
}

/** Scheduled by `insertNotificationOutbox` callers right after they queue an app notification. */
export const drain_notifications = internalAction({
  args: {},
  handler: async (ctx): Promise<DrainOutcome> => await drain(ctx, { app: true, widget: false }),
});

/** Scheduled right after a widget push is queued. */
export const drain_widget_pushes = internalAction({
  args: {},
  handler: async (ctx): Promise<DrainOutcome> => await drain(ctx, { app: false, widget: true }),
});

/**
 * Port of `internal.run_scheduled_push_notification_jobs`, minus the streak
 * reminder enqueue (owned by the streaks module). Drains both outboxes when
 * something is due, including retries whose lease ended.
 */
export const run_scheduled_push_notification_jobs = internalAction({
  args: {},
  handler: async (ctx): Promise<{ due_work: boolean; drain_requested: boolean }> => {
    const dueWork: boolean = await ctx.runQuery(internal.pushQueue.has_due_push_notification_work, {});
    if (!dueWork) return { due_work: false, drain_requested: false };
    const outcome = await drain(ctx, { app: true, widget: true });
    return { due_work: true, drain_requested: outcome.configured };
  },
});
