import { describe, expect, test } from "vitest";
import { dateArg, optionalUuidArg, timestampArg, uuidArg } from "./ids";

describe("uuidArg", () => {
  test("lowercases the uppercase strings iOS sends", () => {
    expect(uuidArg("81000000-0000-0000-0000-00000000ABCD")).toBe("81000000-0000-0000-0000-00000000abcd");
  });

  test("accepts braces and plain hex like Postgres", () => {
    expect(uuidArg("{81000000-0000-0000-0000-000000000001}")).toBe("81000000-0000-0000-0000-000000000001");
    expect(uuidArg("81000000000000000000000000000001")).toBe("81000000-0000-0000-0000-000000000001");
  });

  test("fails with 22P02 and the Postgres message", () => {
    expect(() => uuidArg("not-a-uuid")).toThrow(/22P02/);
    expect(() => uuidArg("not-a-uuid")).toThrow(/invalid input syntax for type uuid: \\"not-a-uuid\\"/);
  });

  test("optional variant maps null and undefined to undefined", () => {
    expect(optionalUuidArg(null)).toBeUndefined();
    expect(optionalUuidArg(undefined)).toBeUndefined();
    expect(optionalUuidArg("81000000-0000-0000-0000-00000000ABCD")).toBe("81000000-0000-0000-0000-00000000abcd");
  });
});

describe("timestampArg", () => {
  test("normalizes offsets and fractional seconds to toISOString form", () => {
    expect(timestampArg("2026-10-10T12:00:00.123Z")).toBe("2026-10-10T12:00:00.123Z");
    expect(timestampArg("2026-10-10T14:00:00+02:00")).toBe("2026-10-10T12:00:00.000Z");
    expect(timestampArg("2026-10-10T12:00:00+00:00")).toBe("2026-10-10T12:00:00.000Z");
  });

  test("fails with 22007", () => {
    expect(() => timestampArg("yesterday-ish")).toThrow(/22007/);
  });
});

describe("dateArg", () => {
  test("accepts real calendar dates only", () => {
    expect(dateArg("2028-02-29")).toBe("2028-02-29");
    expect(() => dateArg("2027-02-29")).toThrow(/22007/);
    expect(() => dateArg("2027-2-9")).toThrow(/22007/);
  });
});
