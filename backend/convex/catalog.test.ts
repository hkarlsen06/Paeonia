import type { FunctionArgs } from "convex/server";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
import { newTest } from "./test.setup";

type Question = FunctionArgs<typeof internal.catalog.sync_catalog>["questions"][number];

function question(key: string, overrides: Partial<Question> = {}): Question {
  return {
    collection: "system",
    key,
    status: "active",
    resurfaceable: true,
    resurface_after_months: 6,
    versions: [version(1, "A memory that stayed")],
    ...overrides,
  };
}

function version(number: number, prompt: string, overrides: Record<string, unknown> = {}) {
  return {
    number,
    status: "active" as const,
    active_from: null,
    retired_at: null,
    answer_kinds: ["text"] as ("text" | "photo" | "voice" | "partner_choice")[],
    localizations: {
      en: { prompt, short_prompt: "Short prompt" },
      nb: { prompt: `${prompt} (nb)`, short_prompt: "Kort" },
    },
    ...overrides,
  };
}

function sync(t: ReturnType<typeof newTest>, questions: Question[], apply: boolean) {
  return t.mutation(internal.catalog.sync_catalog, { questions, apply });
}

describe("sync_catalog", () => {
  test("a dry run reports changes and writes nothing", async () => {
    const t = newTest();
    const result = await sync(t, [question("memory_that_stayed")], false);
    expect(result).toEqual({ changes: ["new question system/memory_that_stayed"], errors: [], applied: false });
    expect(await t.run((ctx) => ctx.db.query("questions").collect())).toEqual([]);
    expect(await t.run((ctx) => ctx.db.query("question_collections").collect())).toEqual([]);
  });

  test("applies a new catalog and makes active questions readable in the app", async () => {
    const t = newTest();
    const draft = question("quiet_draft", { status: "draft", versions: [version(1, "A draft", { status: "draft" })] });
    const result = await sync(t, [question("memory_that_stayed", { resurface_after_months: 3 }), draft], true);
    expect(result.applied).toBe(true);
    expect(result.errors).toEqual([]);
    expect(result.changes).toEqual(["new question system/memory_that_stayed", "new question system/quiet_draft"]);

    const stored = await t.run((ctx) => ctx.db.query("questions").collect());
    expect(stored.map((row) => [row.key, row.status]).sort()).toEqual([
      ["memory_that_stayed", "active"],
      ["quiet_draft", "draft"],
    ]);
    expect(stored.find((row) => row.key === "memory_that_stayed")).toMatchObject({ resurface_after_months: 3 });

    const collections = await t.run((ctx) => ctx.db.query("question_collections").collect());
    expect(collections).toHaveLength(1);
    expect(collections[0]).toMatchObject({ kind: "system", status: "active" });

    // The same catalog again has nothing left to do.
    expect(await sync(t, [question("memory_that_stayed", { resurface_after_months: 3 }), draft], true)).toEqual({
      changes: [],
      errors: [],
      applied: true,
    });
    expect(await t.run((ctx) => ctx.db.query("questions").collect())).toHaveLength(2);
  });

  test("refuses to change an existing version's prompts or answer kinds", async () => {
    const t = newTest();
    await sync(t, [question("memory_that_stayed")], true);

    const edited = question("memory_that_stayed", { versions: [version(1, "A different prompt")] });
    const promptResult = await sync(t, [edited], true);
    expect(promptResult.applied).toBe(false);
    expect(promptResult.errors).toEqual([
      "system/memory_that_stayed/v001/en differs; create a new version instead of editing an existing one",
      "system/memory_that_stayed/v001/nb differs; create a new version instead of editing an existing one",
    ]);

    const kinds = question("memory_that_stayed", { versions: [version(1, "A memory that stayed", { answer_kinds: ["text", "photo"] })] });
    expect((await sync(t, [kinds], true)).errors).toEqual([
      "system/memory_that_stayed/v001 answer_kinds differ; create a new version instead of editing an existing one",
    ]);

    const rows = await t.run((ctx) => ctx.db.query("question_version_localizations").collect());
    expect(rows.map((row) => row.prompt).sort()).toEqual(["A memory that stayed", "A memory that stayed (nb)"]);
    expect(await t.run((ctx) => ctx.db.query("question_answer_kinds").collect())).toHaveLength(1);
  });

  test("an error in one question blocks the whole call", async () => {
    const t = newTest();
    await sync(t, [question("memory_that_stayed")], true);
    const result = await sync(
      t,
      [question("memory_that_stayed", { versions: [version(1, "Edited")] }), question("brand_new_one")],
      true,
    );
    expect(result.applied).toBe(false);
    expect(await t.run((ctx) => ctx.db.query("questions").collect())).toHaveLength(1);
  });

  test("a new version replaces the active one and keeps the old version as history", async () => {
    const t = newTest();
    await sync(t, [question("memory_that_stayed")], true);
    const next = question("memory_that_stayed", {
      versions: [version(1, "A memory that stayed", { status: "retired", retired_at: "2026-10-01T00:00:00.000Z" }), version(2, "A fresher memory")],
    });
    const result = await sync(t, [next], true);
    expect(result.changes).toEqual(["status update for system/memory_that_stayed/v001", "new version system/memory_that_stayed/v002"]);
    const versions = await t.run((ctx) => ctx.db.query("question_versions").collect());
    const byNumber = Object.fromEntries(versions.map((row) => [row.version_number, row]));
    expect(byNumber[1]).toMatchObject({ status: "retired" });
    expect(byNumber[1].retired_at).toBeTruthy();
    expect(byNumber[2]).toMatchObject({ status: "active" });
    expect(byNumber[2].retired_at).toBeUndefined();
    const prompts = await t.run((ctx) =>
      ctx.db
        .query("question_version_localizations")
        .withIndex("by_question_version_id_locale", (q) => q.eq("question_version_id", byNumber[2].id))
        .collect(),
    );
    expect(prompts.map((row) => row.prompt).sort()).toEqual(["A fresher memory", "A fresher memory (nb)"]);
  });

  test("a new version can activate while the old one is still active", async () => {
    const t = newTest();
    await sync(t, [question("memory_that_stayed")], true);
    await sync(t, [question("memory_that_stayed", { versions: [version(1, "A memory that stayed"), version(2, "Second")] })], true);
    const versions = await t.run((ctx) => ctx.db.query("question_versions").collect());
    expect(versions.filter((row) => row.status === "active").map((row) => row.version_number)).toEqual([2]);
  });

  test("rejects active content that is not ready", async () => {
    const t = newTest();
    await expect(
      sync(t, [question("no_kinds", { versions: [version(1, "Nothing to answer with", { answer_kinds: [] })] })], true),
    ).rejects.toThrow(/23514.*active question versions require at least one answer kind/);
    await expect(
      sync(t, [question("three_kinds", { versions: [version(1, "Too many", { answer_kinds: ["text", "photo", "voice"] })] })], true),
    ).rejects.toThrow(/23514.*question versions can have at most two answer kinds/);
    await expect(sync(t, [question("Bad-Key")], true)).rejects.toThrow(/questions_key_check/);
    await expect(
      sync(t, [question("tiny_prompt", { versions: [version(1, "Hi")] })], true),
    ).rejects.toThrow(/question_version_localizations_prompt_check/);
    expect(await t.run((ctx) => ctx.db.query("questions").collect())).toEqual([]);
  });

  test("a draft question can exist without answer kinds", async () => {
    const t = newTest();
    const draft = question("not_ready", { status: "draft", versions: [version(1, "Work in progress", { status: "draft", answer_kinds: [] })] });
    expect((await sync(t, [draft], true)).applied).toBe(true);
    expect((await t.run((ctx) => ctx.db.query("questions").collect())).map((row) => row.status)).toEqual(["draft"]);
  });

  test("reports resurfacing and status changes without touching the prompts", async () => {
    const t = newTest();
    await sync(t, [question("memory_that_stayed")], true);
    const changed = question("memory_that_stayed", { resurfaceable: false, resurface_after_months: null });
    const result = await sync(t, [changed], true);
    expect(result.changes).toEqual(["resurfacing update for system/memory_that_stayed"]);
    const [row] = await t.run((ctx) => ctx.db.query("questions").collect());
    expect(row.resurfaceable).toBe(false);
    expect(row.resurface_after_months).toBeUndefined();
  });
});

describe("seed_subscription_products", () => {
  test("loads the three products and is safe to run twice", async () => {
    const t = newTest();
    expect(await t.mutation(internal.catalog.seed_subscription_products, {})).toBe(3);
    expect(await t.mutation(internal.catalog.seed_subscription_products, {})).toBe(3);
    const rows = await t.run((ctx) => ctx.db.query("subscription_products").collect());
    expect(rows.map((row) => row.apple_product_id).sort()).toEqual([
      "no.paeonia.couple",
      "no.paeonia.couple.year",
      "no.paeonia.streak.restore",
    ]);
    expect(rows.every((row) => row.is_active)).toBe(true);
  });
});
