import type { Doc } from "../_generated/dataModel";

/**
 * The longest pause a phone can ask for. The app offers at most "until morning", so this only
 * stops a broken or hostile client from hiding someone's location for months.
 */
export const MAX_LOCATION_PAUSE_MS = 48 * 3_600_000;

/**
 * Whether the person shares at all right now: sharing is on and not paused. This reads the stored
 * pause and not the clock. The `resume_paused_location_sharing` cron clears a pause when its time
 * passes, so queries that call this re-run then. A mutation that must act on the exact moment
 * compares `paused_until` with `nowIso()` itself.
 */
export function isSharingNow(preference: Doc<"location_sharing_preferences"> | null | undefined): boolean {
  return preference?.is_enabled === true && preference.paused_until === undefined;
}
