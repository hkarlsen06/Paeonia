"use node";

// APNs delivery. Node, because APNs only speaks HTTP/2. The send-time checks and
// result recording are in pushQueue.ts, the pure request builders in lib/apns.ts.

import { v } from "convex/values";
import { connect, type ClientHttp2Session } from "node:http2";
import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import type { PushOutcome } from "./pushQueue";
import {
  apnsHeaders,
  apnsHost,
  buildAppRequest,
  buildWidgetRequest,
  cachedProviderTokens,
  readApnsConfig,
  sendWithEnvironmentFallback,
  type ApnsEnvironment,
  type ApnsHttpResponse,
  type ApnsSendRequest,
  type ApnsSendResult,
  type ApnsTransport,
} from "./lib/apns";

const REQUEST_TIMEOUT_MS = 20_000;

/** One HTTP/2 session per host for one send. The JWT cache lives and dies with it. */
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

/**
 * Sends one outbox row. Each call is one pushWorkpool work item. A network error or any APNs
 * failure other than a dead token throws, so the pool retries it with backoff, and `push_finished`
 * fails the row once the retries run out. A dead token is not retried: `push_finished` retires the
 * device and fails the row.
 *
 * Each send opens its own HTTP/2 session and signs a fresh provider token. A Convex action cannot
 * keep a session open between runs, and at this app's volume one TLS handshake per push is fine.
 */
export const send_push = internalAction({
  args: { kind: v.union(v.literal("app"), v.literal("widget")), outbox_id: v.string() },
  handler: async (ctx, { kind, outbox_id }): Promise<PushOutcome | null> => {
    const config = readApnsConfig(process.env);
    if (config.missing.length > 0) {
      // Local backends have no APNs keys. The row stays unsent, and nothing retries it.
      console.error("push delivery is not configured", { missing: config.missing });
      return null;
    }

    let request: ApnsSendRequest;
    let deviceId: string;
    let queuedEnvironment: ApnsEnvironment;
    if (kind === "app") {
      const notification = await ctx.runMutation(internal.pushQueue.prepare_notification, { outbox_id });
      if (!notification) return null;
      request = buildAppRequest(notification, config.bundleId);
      deviceId = notification.target_device_id;
      queuedEnvironment = notification.apns_environment;
    } else {
      const push = await ctx.runMutation(internal.pushQueue.prepare_widget_push, { outbox_id });
      if (!push) return null;
      request = buildWidgetRequest(push, config.bundleId);
      deviceId = push.target_widget_device_id;
      queuedEnvironment = push.apns_environment;
    }

    const transport = createTransport(config);
    let result: ApnsSendResult;
    try {
      result = await sendWithEnvironmentFallback(request, transport);
    } finally {
      transport.close();
    }

    if (!result.ok && !result.invalidToken) {
      throw new Error(result.error ?? "delivery failed");
    }
    // APNs answered for good. `push_finished` records this in one mutation, and nothing here
    // throws after the send, so the pool never retries a push that already went out.
    return {
      device_id: deviceId,
      provider_message_id: result.providerMessageId,
      error: result.ok ? undefined : (result.error ?? "delivery failed"),
      invalid_token: Boolean(result.invalidToken),
      confirmed_environment:
        result.ok && result.environment && result.environment !== queuedEnvironment ? result.environment : undefined,
    };
  },
});
