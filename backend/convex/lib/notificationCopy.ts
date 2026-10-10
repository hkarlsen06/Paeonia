import type { ReaderCtx } from "./db";
import { isJsonObject, jsonbByteLength, jsonbText } from "./json";

/** Port of `internal.notification_locale_language`: Norwegian locales map to 'nb', everything else to 'en'. */
export function notificationLocaleLanguage(locale: string | null | undefined): "nb" | "en" {
  const normalized = (locale ?? "").trim().replace(/_/g, "-").toLowerCase();
  const language = normalized.split("-")[0];
  return language === "no" || language === "nb" || language === "nn" ? "nb" : "en";
}

const SENSITIVE_PAYLOAD_KEYS =
  /"(answer_body|note_body|message_body|body_text|voice_transcript|media_url|signed_url|latitude|longitude|coordinate|invite_code|report_detail|precise_location)"/i;

/** Port of `internal.notification_payload_is_safe`. */
export function notificationPayloadIsSafe(payload: unknown): boolean {
  return (
    isJsonObject(payload) &&
    jsonbByteLength(payload) <= 4096 &&
    !SENSITIVE_PAYLOAD_KEYS.test(jsonbText(payload))
  );
}

/** Port of `internal.notification_actor_display_name`. Returns null when there is no usable actor name. */
export async function notificationActorDisplayName(
  ctx: ReaderCtx,
  payload: Record<string, unknown>,
): Promise<string | null> {
  const candidates = [payload.actor_user_id, payload.sender_user_id].map((value) =>
    value === undefined || value === null ? "" : String(value).trim(),
  );
  const actorIdText = candidates.find((value) => value !== "");
  if (!actorIdText) {
    return null;
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(actorIdText)) {
    return null;
  }
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", actorIdText.toLowerCase()))
    .unique();
  const name = profile?.display_name?.trim();
  return name ? name : null;
}

/** Port of `internal.notification_alert_body`. Returns null for kinds without alert copy. */
export function notificationAlertBody(
  kind: string,
  payload: Record<string, unknown>,
  locale: string | null | undefined,
): string | null {
  const language = notificationLocaleLanguage(locale);
  const rawDaysLeft = payload.days_left === undefined || payload.days_left === null ? null : String(payload.days_left);
  const daysLeft = Math.max(rawDaysLeft !== null && /^[0-9]+$/.test(rawDaysLeft) ? Number(rawDaysLeft) : 2, 1);
  const nb = language === "nb";
  switch (kind) {
    case "widget_updated":
      return nb ? "La til en ny tegning" : "Added a new drawing";
    case "partner_answered":
      return nb
        ? "Åpne Paeonia for å se hva partneren din skrev."
        : "Open Paeonia to reveal what they wrote.";
    case "daily_challenge_completed":
      return nb
        ? "Åpne Paeonia for å svare og se hva partneren din skrev."
        : "Open Paeonia to answer and reveal what they wrote.";
    case "memory_created":
      return nb ? "Åpne Paeonia for å se det." : "Open Paeonia to see it.";
    case "thread_message_sent":
      if (payload.lock_screen_detail_level === "descriptive") {
        return nb ? "Åpne Paeonia for å svare." : "Open Paeonia to reply.";
      }
      return nb ? "Åpne Paeonia for å se hva som er nytt." : "Open Paeonia to see what's new.";
    case "streak_reminder":
      return nb
        ? "Gjør én liten ting i dag. Rekken fortsetter når dere begge har sjekket inn."
        : "Do one small thing today. Your streak continues once both of you have checked in.";
    case "subscription_trial_reminder":
      return nb
        ? `${daysLeft}${daysLeft === 1 ? " dag igjen. " : " dager igjen. "}Se over abonnementet ditt i App Store.`
        : `${daysLeft}${daysLeft === 1 ? " day left. " : " days left. "}Review your subscription in the App Store.`;
    default:
      return null;
  }
}

/** Port of `internal.notification_alert_title`. */
export async function notificationAlertTitle(
  ctx: ReaderCtx,
  kind: string,
  payload: Record<string, unknown>,
  locale: string | null | undefined,
): Promise<string> {
  const nb = notificationLocaleLanguage(locale) === "nb";
  const actorName = await notificationActorDisplayName(ctx, payload);
  const name = actorName ?? "Paeonia";
  switch (kind) {
    case "widget_updated":
      return name;
    case "partner_answered":
      return nb ? `${name} svarte på samme spørsmål!` : `${name} answered the same question!`;
    case "daily_challenge_completed":
      return nb ? `${name} fullførte dagens spørsmål` : `${name} finished today's questions`;
    case "memory_created":
      return nb ? `${name} la til et nytt minne` : `${name} added a new memory`;
    case "thread_message_sent":
      if (payload.lock_screen_detail_level === "descriptive") {
        return nb
          ? `${actorName ?? "Partneren din"} sendte deg en melding`
          : `${actorName ?? "Your partner"} sent you a message`;
      }
      return "Paeonia";
    case "streak_reminder":
      return nb ? "Sjekk inn før tiden går ut" : "Check in before time runs out";
    case "subscription_trial_reminder":
      return nb ? "Prøveperioden avsluttes snart" : "Your free trial ends soon";
    default:
      return "Paeonia";
  }
}

/** Port of `internal.widget_updated_notification_body`. */
export function widgetUpdatedNotificationBody(locale: string | null | undefined): string {
  return notificationAlertBody("widget_updated", {}, locale) as string;
}

