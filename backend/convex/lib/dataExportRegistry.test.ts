import { describe, expect, test } from "vitest";
import schema from "../schema";
import { renderReadme } from "./dataExportReadme";
import { JsonChunker, dataFilePath, exportPartLimitBytes, partFileName, planParts } from "./dataExportPlan";
import {
  EXPORT_GROUPS,
  TABLE_EXPORTS,
  exportedTablesInOrder,
  isExportableMedia,
  mediaFilePath,
  shapeRow,
  type ExportedTable,
} from "./dataExportRegistry";
import type { Doc } from "../_generated/dataModel";

// The guard that keeps "Download my data" complete. A table in schema.ts must be exported with the
// field that ties its rows to a person, or excluded with a reason. See dataExportRegistry.ts.

type SchemaTable = {
  validator: { fields: Record<string, unknown> };
  " indexes"(): { indexDescriptor: string; fields: string[] }[];
};
const tables = schema.tables as unknown as Record<string, SchemaTable>;
const fieldsOf = (table: string) => Object.keys(tables[table]!.validator.fields);
const indexFields = (table: string, index: string) =>
  tables[table]![" indexes"]().find((candidate) => candidate.indexDescriptor === index)?.fields;
const exported = () =>
  Object.entries(TABLE_EXPORTS).filter((entry): entry is [string, ExportedTable] => entry[1].kind !== "excluded");

describe("the export registry covers the schema", () => {
  test("every table is exported or excluded, and nothing else is listed", () => {
    expect(Object.keys(TABLE_EXPORTS).sort()).toEqual(Object.keys(tables).sort());
  });

  test("every excluded table says why", () => {
    for (const [table, spec] of Object.entries(TABLE_EXPORTS)) {
      if (spec.kind !== "excluded") continue;
      expect(spec.reason.length, `${table} needs a reason`).toBeGreaterThanOrEqual(30);
    }
  });

  test("every exported table ties its rows to the person through a real field and index", () => {
    for (const [table, spec] of exported()) {
      const fields = fieldsOf(table);
      if (spec.kind === "own") {
        expect(fields, `${table}.${spec.field}`).toContain(spec.field);
        expect(indexFields(table, spec.index)?.[0], `${table} index ${spec.index}`).toBe(spec.field);
      } else if (spec.kind === "couple") {
        expect(fields, `${table}.couple_id`).toContain("couple_id");
        expect(indexFields(table, spec.index)?.[0], `${table} index ${spec.index}`).toBe("couple_id");
        if (spec.author) expect(fields, `${table}.${spec.author}`).toContain(spec.author);
        if (spec.referencedBy) {
          const { table: from, field, index } = spec.referencedBy;
          expect(fieldsOf(from), `${from}.${field}`).toContain(field);
          expect(indexFields(from, index), `${from} index ${index}`).toEqual([field, "user_id"]);
          expect(TABLE_EXPORTS[from].kind, `${from} is exported`).toBe("own");
        }
      } else {
        const parent = TABLE_EXPORTS[spec.parent as keyof typeof TABLE_EXPORTS];
        expect(parent.kind, `${table} parent ${spec.parent}`).not.toBe("excluded");
        expect(fieldsOf(spec.parent), `${spec.parent}.${spec.parentKey}`).toContain(spec.parentKey);
        expect(fields, `${table}.${spec.field}`).toContain(spec.field);
        expect(indexFields(table, spec.index)?.[0], `${table} index ${spec.index}`).toBe(spec.field);
      }
      for (const hidden of spec.hide ?? []) expect(fields, `${table} hides ${hidden}`).toContain(hidden);
    }
  });

  test("a parent is always collected before its children", () => {
    const order = exportedTablesInOrder().map(([table]) => table as string);
    expect(order).toHaveLength(exported().length);
    for (const [table, spec] of exported()) {
      if (spec.kind === "child") expect(order.indexOf(spec.parent)).toBeLessThan(order.indexOf(table));
      if (spec.kind === "couple" && spec.referencedBy) expect(order.indexOf(spec.referencedBy.table)).toBeLessThan(order.indexOf(table));
    }
  });

  test("secrets are hidden from the file", () => {
    // Fields that look like secrets must be in `hide`. These only look like secrets: they are the
    // purchase code Apple stores on each of the person's own purchases.
    const notSecrets = new Set(["app_account_tokens.token", "storekit_transactions.app_account_token"]);
    for (const [table, spec] of exported()) {
      for (const field of fieldsOf(table)) {
        if (!/(token|secret|hash|password)/.test(field) || notSecrets.has(`${table}.${field}`)) continue;
        expect(spec.hide ?? [], `${table}.${field} looks like a secret`).toContain(field);
      }
    }
  });

  test("every entry has a group, plain-language text in both languages and no em dash", () => {
    for (const [table, spec] of exported()) {
      expect(EXPORT_GROUPS[spec.group], `${table} group`).toBeDefined();
      for (const text of [spec.about.en, spec.about.nb]) {
        expect(text.length, `${table} text`).toBeGreaterThan(10);
        expect(text).not.toContain("—");
      }
    }
  });
});

describe("what a shared row shows", () => {
  const me = "me";
  const partner = "partner";
  const spec = (table: keyof typeof TABLE_EXPORTS) => TABLE_EXPORTS[table] as ExportedTable;

  test("system fields and hidden fields never leave", () => {
    const row = shapeRow(spec("user_devices"), { _id: "x", _creationTime: 1, id: "d", push_token: "secret", push_token_hash: "h", locale: "nb" }, me);
    expect(row).toEqual({ id: "d", locale: "nb" });
  });

  test("a partner's block on me is not shown, mine is", () => {
    const block = spec("relationship_blocks");
    expect(shapeRow(block, { blocked_by_user_id: partner }, me)).toBeNull();
    expect(shapeRow(block, { blocked_by_user_id: me }, me)).not.toBeNull();
  });

  test("a Draw & Guess word stays hidden from the guesser until the round is over", () => {
    const round = spec("game_moves");
    const open = { drawer_user_id: partner, state: "guessing", word: "giraffe", word_id: "w1" };
    expect(shapeRow(round, open, me)).not.toHaveProperty("word");
    expect(shapeRow(round, { ...open, state: "solved" }, me)).toHaveProperty("word", "giraffe");
    expect(shapeRow(round, { ...open, drawer_user_id: me }, me)).toHaveProperty("word", "giraffe");
  });

  test("a Consensio spot stays hidden from the guesser until they guess", () => {
    const round = spec("consensio_rounds");
    const waiting = { placer_user_id: partner, spot: 0.4 };
    expect(shapeRow(round, waiting, me)).not.toHaveProperty("spot");
    expect(shapeRow(round, { ...waiting, guess: 0.5 }, me)).toHaveProperty("spot", 0.4);
    expect(shapeRow(round, { placer_user_id: me, spot: 0.4 }, me)).toHaveProperty("spot", 0.4);
    expect(shapeRow(spec("consensio_games"), { turn_user_id: partner, choices: [1] }, me)).not.toHaveProperty("choices");
  });

  test("the place of a photo your partner sent stays out, the place of your own stays in", () => {
    const round = spec("guess_my_spot_rounds");
    const sent = { sender_user_id: partner, spot_latitude: 59.9, place_name: "Oslo", points: 3, guess_latitude: 60 };
    expect(shapeRow(round, sent, me)).toEqual({ sender_user_id: partner, points: 3, guess_latitude: 60 });
    expect(shapeRow(round, { ...sent, sender_user_id: me }, me)).toHaveProperty("place_name", "Oslo");
  });

  test("a Story Chain story keeps your lines and only the number and time of your partner's", () => {
    const story = shapeRow(
      spec("story_chain_stories"),
      {
        lines: [
          { id: "1", number: 1, author_user_id: me, text: "mine", created_at: "t1" },
          { id: "2", number: 2, author_user_id: partner, text: "theirs", created_at: "t2" },
        ],
      },
      me,
    );
    expect(story?.lines).toEqual([
      { id: "1", number: 1, author_user_id: me, text: "mine", created_at: "t1" },
      { id: "2", number: 2, author_user_id: partner, created_at: "t2", text_included: false },
    ]);
  });

  test("the hidden photo of a board game is not part of the result", () => {
    const game = shapeRow(spec("board_games"), { photo_media_asset_id: "p", previous: { photo_media_asset_id: "q", moves: [1] }, moves: [2] }, me);
    expect(game).toEqual({ previous: { moves: [1] }, moves: [2] });
  });
});

describe("files", () => {
  const asset = {
    id: "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f",
    created_at: "2026-10-21T08:30:00.000Z",
    upload_purpose: "memory_photo",
    storage_path: "couple/abc/photo.JPG",
    media_type: "image",
  } as const;

  test("a path groups files by what they are", () => {
    expect(mediaFilePath(asset)).toBe(`files/memory-photos/2026-10-21_${asset.id}.jpg`);
    expect(mediaFilePath({ ...asset, upload_purpose: "voice_note", storage_path: "x", media_type: "voice" })).toMatch(/voice-messages\/.*\.m4a$/);
  });

  test("copies kept for a report and removed files stay out", () => {
    const row = { upload_status: "finalized", storage_id: "s", storage_delete_status: "none", bucket: "couple-media", moderation_status: "visible" } as Doc<"media_assets">;
    expect(isExportableMedia(row)).toBe(true);
    expect(isExportableMedia({ ...row, bucket: "report-snapshots" })).toBe(false);
    expect(isExportableMedia({ ...row, moderation_status: "removed" })).toBe(false);
    expect(isExportableMedia({ ...row, storage_delete_status: "pending" })).toBe(false);
    expect(isExportableMedia({ ...row, upload_status: "pending" })).toBe(false);
  });
});

describe("splitting into zip files", () => {
  test("the first zip is shared with the data files, and a file never straddles two zips", () => {
    const files = [10, 40, 40, 30, 90, 5].map((size, index) => ({ id: `f${index}`, size }));
    expect(planParts(files, 60, 100)).toEqual([["f0"], ["f1", "f2"], ["f3"], ["f4", "f5"]]);
  });

  test("a file bigger than a zip gets a zip of its own, and data files alone can fill the first", () => {
    expect(planParts([{ id: "big", size: 500 }], 10, 100)).toEqual([[], ["big"]]);
    expect(planParts([{ id: "a", size: 5 }], 150, 100)).toEqual([[], ["a"]]);
    expect(planParts([], 10, 100)).toEqual([[]]);
  });

  test("names are numbered only when there are several", () => {
    expect(partFileName("2026-10-21", 1, 1)).toBe("Paeonia-my-data-2026-10-21.zip");
    expect(partFileName("2026-10-21", 2, 3)).toBe("Paeonia-my-data-2026-10-21-part-2-of-3.zip");
  });

  test("the deployment can ask for smaller zips", () => {
    expect(exportPartLimitBytes()).toBe(96 * 1024 * 1024);
    process.env.PAEONIA_EXPORT_PART_LIMIT_BYTES = "1000";
    expect(exportPartLimitBytes()).toBe(1000);
    delete process.env.PAEONIA_EXPORT_PART_LIMIT_BYTES;
  });
});

describe("cutting a table into data files", () => {
  const rows = Array.from({ length: 7 }, (_, index) => ({ id: `r${index}`, body: "line\nbreak \"quoted\" æøå", nested: { n: [index, null] } }));

  test("the files hold the same text as one file, in order", () => {
    const chunker = new JsonChunker(150);
    const files: { text: string; rows: number }[] = [];
    for (const row of rows) {
      const done = chunker.add(row);
      if (done) files.push(done);
    }
    const last = chunker.finish();
    if (last) files.push(last);
    expect(files.length).toBeGreaterThan(1);
    expect(files.map((file) => file.rows).reduce((a, b) => a + b, 0)).toBe(rows.length);
    expect(files.flatMap((file) => JSON.parse(file.text))).toEqual(rows);
    const whole = new JsonChunker(Number.MAX_SAFE_INTEGER);
    for (const row of rows) whole.add(row);
    expect(whole.finish()?.text).toBe(JSON.stringify(rows, null, 2));
  });

  test("an empty table makes no file", () => {
    expect(new JsonChunker(10).finish()).toBeNull();
  });

  test("a table with several files gets numbered names", () => {
    expect(dataFilePath("chat", "thread_messages", 0, 1)).toBe("chat/thread_messages.json");
    expect(dataFilePath("chat", "thread_messages", 1, 12)).toBe("chat/thread_messages-002.json");
  });
});

describe("the README", () => {
  const input = {
    generatedAt: "2026-10-21T08:30:00.000Z",
    userId: "u1",
    includeFiles: true,
    partNames: ["a.zip", "b.zip"],
    files: [{ path: "account/users.json", group: "account" as const, rows: 1, about: "Your account." }],
    mediaCount: 3,
    mediaSkippedCount: 1,
  };

  test("names the files, the processors, the retention and Datatilsynet in both languages", () => {
    const en = renderReadme({ ...input, locale: "en" });
    const nb = renderReadme({ ...input, locale: "nb" });
    for (const text of [en, nb]) {
      expect(text).toContain("account/users.json");
      expect(text).toContain("Datatilsynet");
      expect(text).toContain("Clerk");
      expect(text).toContain("PostHog");
      expect(text).toContain("contact@paeonia.no");
      expect(text).toContain("b.zip");
      expect(text).not.toContain("—");
    }
    expect(en).toContain("Part 1");
    expect(nb).toContain("Del 1");
  });
});
