import { v, type Infer } from "convex/values";
import { fail } from "./errors";
import { btrimToNull, charLength } from "./text";

// A place a partner picked on the map for a memory or a visit. City and country are stored with it
// so the memories map can count places without looking addresses up.

const optString = v.optional(v.string());

/** The stored shape, shared by `memories.place` and `visits.place`. */
export const placeField = v.object({
  name: v.string(),
  latitude: v.number(),
  longitude: v.number(),
  city: optString,
  country_code: optString,
});

export type Place = Infer<typeof placeField>;

/** The argument the app sends. Null or a missing key means "no place". */
export const placeArg = v.optional(
  v.union(
    v.null(),
    v.object({
      name: v.string(),
      latitude: v.number(),
      longitude: v.number(),
      city: v.optional(v.union(v.null(), v.string())),
      country_code: v.optional(v.union(v.null(), v.string())),
    }),
  ),
);

/**
 * Checks a place sent by the app and trims its text. Null means "no place". The name is required,
 * the coordinates must be on the globe, and the country is an ISO 3166 two-letter code. `owner`
 * names the row in the error, such as "memory".
 */
export function normalizePlace(place: Infer<typeof placeArg>, owner: string): Place | null {
  if (place === null || place === undefined) return null;
  const name = btrimToNull(place.name);
  if (name === null) return fail("23514", `${owner} place name is required`);
  if (charLength(name) > 160) return fail("23514", `${owner} place name is too long`);
  const { latitude, longitude } = place;
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    return fail("23514", `${owner} place latitude is out of range`);
  }
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return fail("23514", `${owner} place longitude is out of range`);
  }
  const city = btrimToNull(place.city);
  if (city !== null && charLength(city) > 120) return fail("23514", `${owner} place city is too long`);
  const countryCode = btrimToNull(place.country_code);
  if (countryCode !== null && !/^[A-Z]{2}$/.test(countryCode)) {
    return fail("23514", `${owner} place country code is not valid`);
  }
  return {
    name,
    latitude,
    longitude,
    ...(city === null ? {} : { city }),
    ...(countryCode === null ? {} : { country_code: countryCode }),
  };
}
