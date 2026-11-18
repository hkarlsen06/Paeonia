#!/usr/bin/env node
// Checks rules that span the backend, the relay, the iOS app and the marketing site, so no
// single compiler sees them. Run from anywhere: `node scripts/check-repo-rules.mjs`.
// `--staged` checks the files as staged, which the pre-commit hook uses so that another
// agent's unstaged edits in the same checkout don't decide this commit.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const tracked = (...globs) =>
  execFileSync("git", ["ls-files", "-z", "--", ...globs], { cwd: root, encoding: "utf8" })
    .split("\0")
    .filter(Boolean);

const GAME_KINDS_FILE = "backend/convex/lib/validators.ts";
const RELAY_TICKET_FILE = "relay/src/ticket.ts";
const SWIFT_GAME_KIND_FILE = "ios/PaeoniaApp/Features/Games/Models/GameKind.swift";
const SWIFT_TRIAL_FILE = "ios/PaeoniaApp/Services/Subscription/PaeoniaSubscriptionModels.swift";
const BACKEND_TRIAL_FILE = "backend/convex/storekit.ts";
const TERMS_VERSION_FILE = "backend/convex/lib/terms.ts";
const TERMS_TEXT_FILE = "marketing/src/lib/i18n/dictionaries/legal.en.ts";
const PACKAGE_PINS_FILE = "ios/Paeonia.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved";
const PACKAGE_LICENCES_FILE = "ios/PaeoniaApp/Resources/Licences/PackageLicences.txt";
const userVisible = [
  ...tracked("*.xcstrings", "ios/app-store/metadata", "marketing/src", "marketing/static"),
  ...tracked("backend/convex/*.ts", "backend/convex/lib/*.ts").filter((path) => !/\.(test|testing|setup|fixtures)\.ts$|\/_generated\//.test(path)),
];

let base = root;
if (process.argv.includes("--staged")) {
  base = mkdtempSync(join(tmpdir(), "paeonia-repo-rules-"));
  process.on("exit", () => rmSync(base, { recursive: true, force: true }));
  const inputs = new Set([
    GAME_KINDS_FILE, RELAY_TICKET_FILE, SWIFT_GAME_KIND_FILE, SWIFT_TRIAL_FILE, BACKEND_TRIAL_FILE,
    TERMS_VERSION_FILE, TERMS_TEXT_FILE, PACKAGE_PINS_FILE, PACKAGE_LICENCES_FILE, ...userVisible,
  ]);
  execFileSync("git", ["checkout-index", "-z", "--stdin", `--prefix=${base}/`], { cwd: root, input: [...inputs].join("\0") });
}
const read = (path) => readFileSync(join(base, path), "utf8");

const failures = [];
const fail = (message) => failures.push(message);

function quotedList(path, pattern) {
  const block = read(path).match(pattern)?.[1];
  if (!block) throw new Error(`${path}: could not find the list (${pattern})`);
  return [...block.matchAll(/"([a-z_]+)"/g)].map((match) => match[1]);
}

function sameSet(name, expected, actual) {
  const missing = expected.filter((kind) => !actual.includes(kind));
  const extra = actual.filter((kind) => !expected.includes(kind));
  if (missing.length || extra.length) {
    fail(`${name} differs from GAME_KINDS. Missing: ${missing.join(", ") || "none"}. Extra: ${extra.join(", ") || "none"}.`);
  }
}

// Every game kind exists on all three sides. The relay refuses a ticket for a channel it does
// not list, and the app cannot decode a kind it has no case for.
const gameKinds = quotedList(GAME_KINDS_FILE, /export const GAME_KINDS = \[([^\]]*)\]/);
const relayChannels = quotedList(RELAY_TICKET_FILE, /export const ALLOWED_CHANNELS[^=]*= \[([^\]]*)\]/);
const swiftKinds = [...read(SWIFT_GAME_KIND_FILE).matchAll(/^\s*case \w+ = "([a-z_]+)"/gm)].map(
  (match) => match[1],
);
sameSet("ALLOWED_CHANNELS in relay/src/ticket.ts (without `call`)", gameKinds, relayChannels.filter((channel) => channel !== "call"));
if (!relayChannels.includes("call")) fail("ALLOWED_CHANNELS in relay/src/ticket.ts must list `call`.");
sameSet("GameKind in ios/PaeoniaApp/Features/Games/Models/GameKind.swift", gameKinds, swiftKinds);

// "Connect Four" is a Hasbro trademark, so no text a person reads may use it. The game is
// "Four in a Row" ("Fire på rad"). The internal names `connect_four`, `connectFour` and
// `connect-four` stay. Comments and tests may name the original game.
const trademark = /connect\s+(four|4)\b/i;
for (const path of userVisible) {
  read(path)
    .split("\n")
    .forEach((line, index) => {
      if (path.endsWith(".ts") && /^\s*(\/\/|\/?\*)/.test(line)) return;
      if (trademark.test(line)) fail(`${path}:${index + 1} says "Connect Four". Use "Four in a Row".`);
    });
}

// The paywall promises a reminder this many days before the trial ends, and the backend sends it.
const swiftTrialDays = read(SWIFT_TRIAL_FILE).match(
  /static let reminderDaysBeforeEnd = (\d+)/,
)?.[1];
const backendTrialDays = read(BACKEND_TRIAL_FILE).match(/const TRIAL_REMINDER_DAYS_BEFORE_END = (\d+)/)?.[1];
if (!swiftTrialDays || !backendTrialDays) {
  fail("Could not find PaeoniaFreeTrial.reminderDaysBeforeEnd or TRIAL_REMINDER_DAYS_BEFORE_END.");
} else if (swiftTrialDays !== backendTrialDays) {
  fail(
    `PaeoniaFreeTrial.reminderDaysBeforeEnd is ${swiftTrialDays} but TRIAL_REMINDER_DAYS_BEFORE_END in backend/convex/storekit.ts is ${backendTrialDays}.`,
  );
}

// A new account stores TERMS_VERSION as the terms it agreed to, so it must be the date on the terms.
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const termsVersion = read(TERMS_VERSION_FILE).match(/export const TERMS_VERSION = "(\d{4}-\d{2}-\d{2})"/)?.[1];
const termsUpdated = read(TERMS_TEXT_FILE).match(/\n  terms: \{[\s\S]*?\n    updated: 'Last updated (\d{1,2}) (\w+) (\d{4})'/);
if (!termsVersion || !termsUpdated || !MONTHS.includes(termsUpdated[2])) {
  fail(`Could not find TERMS_VERSION in ${TERMS_VERSION_FILE} or the terms' "Last updated" date in ${TERMS_TEXT_FILE}.`);
} else {
  const [, day, month, year] = termsUpdated;
  const termsDate = `${year}-${String(MONTHS.indexOf(month) + 1).padStart(2, "0")}-${day.padStart(2, "0")}`;
  if (termsVersion !== termsDate) {
    fail(`TERMS_VERSION in ${TERMS_VERSION_FILE} is ${termsVersion} but the terms in ${TERMS_TEXT_FILE} say ${termsDate}.`);
  }
}

// The Licences screen lists every Swift package the app links, at the version it links.
const licenceHeadings = read(PACKAGE_LICENCES_FILE)
  .split("\n\f\n")
  .map((entry) => entry.split("\n", 1)[0]);
const pinHeadings = JSON.parse(read(PACKAGE_PINS_FILE)).pins.map(
  ({ location, state }) => `${location.replace(/\/$/, "").split("/").pop().replace(/\.git$/, "")} ${state.version ?? state.revision.slice(0, 12)}`,
);
if ([...licenceHeadings].sort().join("\n") !== [...pinHeadings].sort().join("\n")) {
  fail(`${PACKAGE_LICENCES_FILE} does not match Package.resolved. Run ios/Scripts/collect-package-licences.py.`);
}

if (failures.length) {
  for (const message of failures) console.error(`check-repo-rules: ${message}`);
  process.exit(1);
}
console.log("check-repo-rules: ok");
