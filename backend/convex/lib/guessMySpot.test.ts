import { describe, expect, test } from "vitest";
import { coordinateArg, haversineMeters, isTakenOn, placeNameArg, pointsFor } from "./guessMySpot";

describe("scoring", () => {
  test("halves every 1,500 km from 5000", () => {
    const cases: [number, number][] = [[200, 5000], [10_000, 4977], [100_000, 4774], [500_000, 3969], [1_500_000, 2500], [5_000_000, 496], [20_000_000, 0]];
    for (const [meters, points] of cases) expect(pointsFor(meters), `${meters} m`).toBe(points);
  });

  test("measures the great circle in metres", () => {
    const oslo = { latitude: 59.9139, longitude: 10.7522 };
    const bergen = { latitude: 60.3913, longitude: 5.3221 };
    expect(haversineMeters(oslo, bergen)).toBeGreaterThan(300_000);
    expect(haversineMeters(oslo, bergen)).toBeLessThan(310_000);
    expect(haversineMeters(oslo, oslo)).toBe(0);
    // Across the antimeridian it takes the short way.
    expect(haversineMeters({ latitude: 0, longitude: 179.5 }, { latitude: 0, longitude: -179.5 })).toBeLessThan(112_000);
  });
});

describe("input rules", () => {
  test("coordinates are in range and rounded to 6 decimals", () => {
    expect(coordinateArg(60.12345678, 5.987654321)).toEqual({ latitude: 60.123457, longitude: 5.987654 });
    expect(coordinateArg(90.0001, 0)).toBe("latitude");
    expect(coordinateArg(Number.NaN, 0)).toBe("latitude");
    expect(coordinateArg(0, -180.5)).toBe("longitude");
    expect(coordinateArg(0, Number.POSITIVE_INFINITY)).toBe("longitude");
  });

  test("place names are trimmed, short and plain", () => {
    expect(placeNameArg("  Bergen,\n Norway ")).toBe("Bergen, Norway");
    expect(placeNameArg("   ")).toBeUndefined();
    expect(placeNameArg(null)).toBeUndefined();
    expect(placeNameArg("x".repeat(121))).toBe("invalid");
    expect(placeNameArg("Ber\u0007gen")).toBe("invalid");
    expect(placeNameArg("Tromsø 🏔️")).toBe("Tromsø 🏔️");
  });

  test("the date is a real day no later than tomorrow", () => {
    const now = Date.parse("2026-10-18T12:00:00.000Z");
    expect(isTakenOn("2024-06-12", now)).toBe(true);
    expect(isTakenOn("2026-10-19", now)).toBe(true);
    expect(isTakenOn("2026-10-20", now)).toBe(false);
    expect(isTakenOn("2024-02-30", now)).toBe(false);
    expect(isTakenOn("2024-6-12", now)).toBe(false);
  });
});
