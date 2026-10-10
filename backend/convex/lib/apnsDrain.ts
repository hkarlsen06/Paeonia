import type { FunctionReference } from "convex/server";
import { internal } from "../_generated/api";
import {
  buildAppRequest,
  buildWidgetRequest,
  errorMessage,
  type ApnsSendRequest,
  type ApnsSendResult,
  type ClaimedNotification,
  type ClaimedWidgetPush,
} from "./apns";

export type DrainStats = { claimed: number; sent: number; failed: number };

/** The two calls the drain makes. An action context and a convex-test handle both fit. */
export type DrainCtx = {
  runMutation: (reference: FunctionReference<"mutation", "internal">, args: any) => Promise<any>;
};

export type ApnsSender = (request: ApnsSendRequest) => Promise<ApnsSendResult>;

const BATCH_LIMIT = 100;

async function safeSend(send: ApnsSender, request: ApnsSendRequest): Promise<ApnsSendResult> {
  try {
    return await send(request);
  } catch (error) {
    return { ok: false, error: errorMessage(error) };
  }
}

/** Claims a batch of app notifications, sends each, and records the result. */
export async function drainAppNotifications(
  ctx: DrainCtx,
  send: ApnsSender,
  bundleId: string,
): Promise<DrainStats> {
  const batch: ClaimedNotification[] = await ctx.runMutation(internal.pushQueue.claim_notification_batch, {
    p_limit: BATCH_LIMIT,
  });
  let sent = 0;
  let failed = 0;

  for (const notification of batch) {
    const result = await safeSend(send, buildAppRequest(notification, bundleId));

    // Remember the host APNs accepted so later sends skip the fallback.
    if (result.ok && result.environment && result.environment !== notification.apns_environment) {
      await ctx.runMutation(internal.pushQueue.persist_device_environment, {
        kind: "app",
        device_id: notification.target_device_id,
        apns_environment: result.environment,
      });
    }
    if (result.invalidToken) {
      await ctx.runMutation(internal.pushQueue.disable_device, {
        kind: "app",
        device_id: notification.target_device_id,
      });
    }

    try {
      await ctx.runMutation(internal.pushQueue.mark_notification_result, {
        p_outbox_id: notification.outbox_id,
        p_success: result.ok,
        p_provider_message_id: result.providerMessageId ?? null,
        p_error: result.error ?? null,
        p_invalid_token: result.invalidToken ?? false,
      });
    } catch (error) {
      console.error("Unable to record notification result", {
        outbox_id: notification.outbox_id,
        error: errorMessage(error),
      });
      failed += 1;
      continue;
    }
    if (result.ok) sent += 1;
    else failed += 1;
  }
  return { claimed: batch.length, sent, failed };
}

/** Claims a batch of widget pushes, sends each, and records the result. */
export async function drainWidgetPushes(
  ctx: DrainCtx,
  send: ApnsSender,
  bundleId: string,
): Promise<DrainStats> {
  const batch: ClaimedWidgetPush[] = await ctx.runMutation(internal.pushQueue.claim_widget_push_batch, {
    p_limit: BATCH_LIMIT,
  });
  let sent = 0;
  let failed = 0;

  for (const notification of batch) {
    const result = await safeSend(send, buildWidgetRequest(notification, bundleId));

    if (result.ok && result.environment && result.environment !== notification.apns_environment) {
      await ctx.runMutation(internal.pushQueue.persist_device_environment, {
        kind: "widget",
        device_id: notification.target_widget_device_id,
        apns_environment: result.environment,
      });
    }
    if (result.invalidToken) {
      await ctx.runMutation(internal.pushQueue.disable_device, {
        kind: "widget",
        device_id: notification.target_widget_device_id,
      });
    }

    try {
      await ctx.runMutation(internal.pushQueue.mark_widget_push_result, {
        p_outbox_id: notification.outbox_id,
        p_success: result.ok,
        p_provider_message_id: result.providerMessageId ?? null,
        p_error: result.error ?? null,
        p_invalid_token: result.invalidToken ?? false,
      });
    } catch (error) {
      console.error("Unable to record WidgetKit push result", {
        outbox_id: notification.outbox_id,
        error: errorMessage(error),
      });
      failed += 1;
      continue;
    }
    if (result.ok) sent += 1;
    else failed += 1;
  }
  return { claimed: batch.length, sent, failed };
}
