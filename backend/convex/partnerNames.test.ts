/// <reference types="vite/client" />
import { describe, expect, test } from "vitest";
import { normalizePartnerNickname, PARTNER_NICKNAME_MAX_LENGTH } from "./lib/partnerNames";

/**
 * Files that may read `profiles.display_name`, with the reason. Everything else that puts a partner's
 * name in copy, an API field or a push must call `nameForViewer` (or `nameAndSourceForViewer`) from
 * `lib/partnerNames.ts`, because the viewer may have given the partner a nickname.
 */
const MAY_READ_DISPLAY_NAME: Record<string, string> = {
  "./schema.ts": "table definition",
  "./lib/partnerNames.ts": "the resolver",
  "./identity.ts": "the user's own profile",
  "./lib/profiles.ts": "the user's own profile rows",
  "./lib/auth.ts": "provider name sync into the user's own profile",
  "./accountDeletion.ts": "clears the user's own name",
  "./lib/reviewAccess.ts": "creates the App Review demo partner",
  "./review.ts": "creates the App Review demo partner",
  "./admin.ts": "operator tools, which show account names on purpose",
  "./lib/reportTargets.ts": "moderation snapshots show the reported account name",
  "./pairing.ts": "the invite preview, shown before the two people are a couple",
};

const sources = import.meta.glob(
  ["./**/*.ts", "!./**/*.test.ts", "!./_generated/**", "!./**/*.testing.ts", "!./**/*.testHelpers.ts", "!./**/*.setup.ts", "!./**/*.fixtures.ts"],
  { query: "?raw", import: "default", eager: true },
) as Record<string, string>;
const READS_DISPLAY_NAME = /(?<![A-Za-z0-9_])display_name(?![A-Za-z0-9_])/;

describe("partner names", () => {
  test("only the allow-listed files read display_name", () => {
    expect(Object.keys(sources).length).toBeGreaterThan(50);
    const offenders = Object.entries(sources)
      .filter(([path, text]) => !(path in MAY_READ_DISPLAY_NAME) && READS_DISPLAY_NAME.test(text))
      .map(([path]) => path)
      .sort();
    expect(
      offenders,
      "These files read display_name. Use nameForViewer(ctx, viewerUserId, subjectUserId) from lib/partnerNames.ts so the viewer's nickname for their partner applies, or add the file to MAY_READ_DISPLAY_NAME with a reason.",
    ).toEqual([]);
  });

  test("every allow-listed file still reads display_name", () => {
    const stale = Object.keys(MAY_READ_DISPLAY_NAME).filter((path) => !READS_DISPLAY_NAME.test(sources[path] ?? ""));
    expect(stale).toEqual([]);
  });
});

describe("normalizePartnerNickname", () => {
  test("trims, collapses whitespace and turns empty input into no nickname", () => {
    expect(normalizePartnerNickname("  Ellie \n 🌸 ")).toBe("Ellie 🌸");
    expect(normalizePartnerNickname("   ")).toBeNull();
    expect(normalizePartnerNickname(null)).toBeNull();
  });

  test("allows exactly the maximum and refuses one more", () => {
    expect(normalizePartnerNickname("a".repeat(PARTNER_NICKNAME_MAX_LENGTH))).not.toBeNull();
    expect(() => normalizePartnerNickname("a".repeat(PARTNER_NICKNAME_MAX_LENGTH + 1))).toThrow(/23514/);
  });
});
