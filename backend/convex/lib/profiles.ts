import type { Doc } from "../_generated/dataModel";
import { findCurrentCouple } from "./access";
import { getByUuid, orNull, withTouch, type ReaderCtx, type WriterCtx } from "./db";
import { fail } from "./errors";
import { queueOldMediaAssetIfOrphaned } from "./mediaOrphans";
import { enqueueLockScreenRefreshForPartner, LOCK_SCREEN_REFRESH_DELAY_SECONDS } from "./notifications";
import { refreshStreakAfterProfileTimeZoneChange } from "./streaks";

type ProfileColumns = Omit<Doc<"profiles">, "_id" | "_creationTime" | "user_id" | "revision" | "created_at" | "updated_at">;

/** Columns a patch may change. A key set to `undefined` clears the column. */
export type ProfilePatch = Partial<ProfileColumns>;

const PHOTO_COLUMNS = [
  "profile_photo_asset_id",
  "provider_profile_photo_asset_id",
  "provider_profile_photo_source",
  "deleted_at",
] as const;

/** The profile columns an app user could read through column grants, with SQL nulls. */
export function profileRow(profile: Doc<"profiles">) {
  return {
    user_id: profile.user_id,
    display_name: orNull(profile.display_name),
    profile_photo_asset_id: orNull(profile.profile_photo_asset_id),
    time_zone_id: orNull(profile.time_zone_id),
    time_zone_updated_at: orNull(profile.time_zone_updated_at),
    onboarding_completed_at: orNull(profile.onboarding_completed_at),
    revision: profile.revision,
    moderation_status: profile.moderation_status,
    created_at: profile.created_at,
    updated_at: profile.updated_at,
    deleted_at: orNull(profile.deleted_at),
    provider_profile_photo_asset_id: orNull(profile.provider_profile_photo_asset_id),
    provider_profile_photo_source: orNull(profile.provider_profile_photo_source),
  };
}

/** The eight columns `update_own_profile` and `set_own_provider_profile_photo` returned. */
export function profileSummaryRow(profile: Doc<"profiles">) {
  return {
    user_id: profile.user_id,
    display_name: orNull(profile.display_name),
    time_zone_id: orNull(profile.time_zone_id),
    time_zone_updated_at: orNull(profile.time_zone_updated_at),
    onboarding_completed_at: orNull(profile.onboarding_completed_at),
    profile_photo_asset_id: orNull(profile.profile_photo_asset_id),
    provider_profile_photo_asset_id: orNull(profile.provider_profile_photo_asset_id),
    provider_profile_photo_source: orNull(profile.provider_profile_photo_source),
  };
}

export async function findProfile(ctx: ReaderCtx, userId: string): Promise<Doc<"profiles"> | null> {
  return await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
}

/**
 * Port of the `assert_profile_photo_asset_owner` trigger. Returns the patch with
 * the photo columns cleared when the profile is being deleted.
 */
async function assertProfilePhotoAssetOwner(
  ctx: WriterCtx,
  next: Doc<"profiles">,
): Promise<{ clear: boolean }> {
  if (next.deleted_at !== undefined) {
    return { clear: true };
  }
  if ((next.provider_profile_photo_asset_id === undefined) !== (next.provider_profile_photo_source === undefined)) {
    fail("23514", "provider profile photo asset and source must be set together");
  }
  if (next.provider_profile_photo_source !== undefined && next.provider_profile_photo_source !== "google") {
    fail("23514", "provider profile photo source is not supported");
  }
  for (const assetId of [next.profile_photo_asset_id, next.provider_profile_photo_asset_id]) {
    if (assetId === undefined) {
      continue;
    }
    const asset = await getByUuid(ctx, "media_assets", assetId);
    if (!asset) {
      fail("23503", "profile photo asset was not found");
    }
    if (
      asset.owner_user_id !== next.user_id ||
      asset.bucket !== "profile-photos" ||
      asset.media_type !== "image" ||
      asset.upload_status !== "finalized" ||
      asset.storage_delete_status !== "none" ||
      asset.moderation_status !== "visible" ||
      asset.deleted_at !== undefined
    ) {
      fail("23514", "profile photo asset is not usable");
    }
  }
  return { clear: false };
}

/**
 * Write helper for every `profiles` patch. Replaces the profile triggers:
 * `touch_updated_at_and_revision`, `assert_profile_photo_asset_owner`, the
 * orphaned profile photo queueing, and
 * `refresh_streak_after_profile_time_zone_change`. Returns the updated row.
 */
export async function updateProfile(
  ctx: WriterCtx,
  profile: Doc<"profiles">,
  patch: ProfilePatch,
): Promise<Doc<"profiles">> {
  let effective: ProfilePatch = patch;
  const photoRelated = PHOTO_COLUMNS.some((column) => column in patch);
  if (photoRelated) {
    const { clear } = await assertProfilePhotoAssetOwner(ctx, { ...profile, ...patch });
    if (clear) {
      effective = {
        ...patch,
        profile_photo_asset_id: undefined,
        provider_profile_photo_asset_id: undefined,
        provider_profile_photo_source: undefined,
      };
    }
  }
  await ctx.db.patch(profile._id, withTouch(profile, effective));
  const updated = (await ctx.db.get(profile._id))!;

  if (photoRelated) {
    const deletedNow = profile.deleted_at === undefined && updated.deleted_at !== undefined;
    const oldIds: string[] = [];
    if (
      profile.profile_photo_asset_id !== undefined &&
      (profile.profile_photo_asset_id !== updated.profile_photo_asset_id || deletedNow)
    ) {
      oldIds.push(profile.profile_photo_asset_id);
    }
    if (
      profile.provider_profile_photo_asset_id !== undefined &&
      (profile.provider_profile_photo_asset_id !== updated.provider_profile_photo_asset_id || deletedNow)
    ) {
      oldIds.push(profile.provider_profile_photo_asset_id);
    }
    await queueOldMediaAssetIfOrphaned(ctx, ...oldIds);
  }
  await refreshStreakAfterProfileTimeZoneChange(ctx, updated.user_id, profile.time_zone_id, updated.time_zone_id);
  // The partner's Lock Screen widget shows this person's name and local time.
  if (profile.time_zone_id !== updated.time_zone_id || profile.display_name !== updated.display_name) {
    const couple = await findCurrentCouple(ctx, updated.user_id);
    if (couple) {
      await enqueueLockScreenRefreshForPartner(ctx, {
        couple_id: couple.id,
        actor_user_id: updated.user_id,
        delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
      });
    }
  }
  return updated;
}
