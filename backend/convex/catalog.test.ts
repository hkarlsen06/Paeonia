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

  test("a new version moves the question's daily instances to it", async () => {
    const t = newTest();
    await sync(t, [question("memory_that_stayed")], true);
    const [v1] = await t.run((ctx) => ctx.db.query("question_versions").collect());
    await t.run(async (ctx) => {
      await ctx.db.insert("daily_question_instances", {
        id: crypto.randomUUID(),
        couple_day_id: crypto.randomUUID(),
        couple_id: crypto.randomUUID(),
        question_id: v1.question_id,
        question_version_id: v1.id,
        status: "active",
        created_at: "2026-10-01T00:00:00.000Z",
      });
    });
    const next = question("memory_that_stayed", {
      versions: [version(1, "A memory that stayed", { status: "retired", retired_at: "2026-10-02T00:00:00.000Z" }), version(2, "A fresher memory")],
    });
    await sync(t, [next], true);
    const v2 = await t.run((ctx) =>
      ctx.db.query("question_versions").filter((q) => q.eq(q.field("version_number"), 2)).unique(),
    );
    const instances = await t.run((ctx) => ctx.db.query("daily_question_instances").collect());
    expect(instances.map((row) => row.question_version_id)).toEqual([v2!.id]);
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

describe("sync_catalog topics", () => {
  const topic = {
    key: "travel_and_places",
    status: "active" as const,
    sort_order: 4,
    private: false,
    localizations: {
      en: { title: "Travel and places", subtitle: "Where you've been." },
      nb: { title: "Reiser og steder", subtitle: "Hvor du har vært." },
    },
  };
  const topicQuestion = (key: string, sortOrder: number) =>
    question(key, { collection: "topic", topic: topic.key, sort_order: sortOrder, resurfaceable: false, resurface_after_months: null });

  test("writes the topic, its names and its ordered questions, apart from the daily collection", async () => {
    const t = newTest();
    const result = await t.mutation(internal.catalog.sync_catalog, {
      questions: [topicQuestion("travel_best_view", 1), topicQuestion("travel_best_walk", 14)],
      topics: [topic],
      apply: true,
    });
    expect(result.errors).toEqual([]);
    expect(result.changes).toContain("new topic travel_and_places");
    const collections = await t.run((ctx) => ctx.db.query("question_collections").collect());
    expect(collections).toMatchObject([{ kind: "topic", key: "travel_and_places", sort_order: 4, private: false, status: "active" }]);
    const names = await t.run((ctx) => ctx.db.query("question_collection_localizations").collect());
    expect(names.map((row) => [row.locale, row.title]).sort()).toEqual([
      ["en", "Travel and places"],
      ["nb", "Reiser og steder"],
    ]);
    const stored = await t.run((ctx) => ctx.db.query("questions").collect());
    expect(stored.map((row) => [row.key, row.sort_order, row.collection_id === collections[0].id]).sort()).toEqual([
      ["travel_best_view", 1, true],
      ["travel_best_walk", 14, true],
    ]);

    const again = await t.mutation(internal.catalog.sync_catalog, {
      questions: [topicQuestion("travel_best_view", 1), topicQuestion("travel_best_walk", 14)],
      topics: [topic],
      apply: false,
    });
    expect(again.changes).toEqual([]);
  });

  test("keeps the topic catalog row the topic reads use in line with the topic", async () => {
    const t = newTest();
    const questions = [topicQuestion("travel_best_walk", 14), topicQuestion("travel_best_view", 1)];
    await t.mutation(internal.catalog.sync_catalog, { questions, topics: [topic], apply: true });
    const rows = await t.run((ctx) => ctx.db.query("topic_catalog").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ key: "travel_and_places", sort_order: 4, title_nb: "Reiser og steder" });
    expect(rows[0].questions.map((item) => [item.question_key, item.sort_order, item.prompt_nb])).toEqual([
      ["travel_best_view", 1, "A memory that stayed (nb)"],
      ["travel_best_walk", 14, "A memory that stayed (nb)"],
    ]);

    // A deployment that has the topic but no row yet (a fresh deploy) is rebuilt by the next sync, even with nothing else to change.
    await t.run(async (ctx) => await ctx.db.delete(rows[0]._id));
    const dry = await t.mutation(internal.catalog.sync_catalog, { questions, topics: [topic], apply: false });
    expect(dry.changes).toEqual(["topic catalog rebuild for travel_and_places"]);
    await t.mutation(internal.catalog.sync_catalog, { questions, topics: [topic], apply: true });
    expect(await t.run((ctx) => ctx.db.query("topic_catalog").collect())).toHaveLength(1);

    await t.mutation(internal.catalog.sync_catalog, { questions, topics: [{ ...topic, status: "retired" }], apply: true });
    expect(await t.run((ctx) => ctx.db.query("topic_catalog").collect())).toEqual([]);
  });

  test("a topic question without its topic in the payload is an error", async () => {
    const t = newTest();
    const result = await t.mutation(internal.catalog.sync_catalog, {
      questions: [topicQuestion("travel_best_view", 1)],
      apply: true,
    });
    expect(result.errors).toEqual(["topic/travel_and_places/travel_best_view names a topic that is not in the catalog"]);
    expect(result.applied).toBe(false);
  });
});

describe("sync_catalog pick one of two", () => {
  const withOptions = (overrides: Record<string, unknown> = {}) =>
    version(1, "Sea or mountains?", {
      answer_kinds: ["either_or", "text"],
      localizations: {
        en: { prompt: "Sea or mountains?", short_prompt: "Sea or mountains", option_a: "By the sea", option_b: "In the mountains" },
        nb: { prompt: "Sjø eller fjell?", short_prompt: "Sjø eller fjell", option_a: "Ved sjøen", option_b: "På fjellet" },
      },
      ...overrides,
    });

  test("stores the labels with the version", async () => {
    const t = newTest();
    const result = await sync(t, [question("sea_or_mountains", { versions: [withOptions()] })], true);
    expect(result.errors).toEqual([]);
    const rows = await t.run((ctx) => ctx.db.query("question_version_localizations").collect());
    expect(rows.map((row) => [row.locale, row.option_a, row.option_b]).sort()).toEqual([
      ["en", "By the sea", "In the mountains"],
      ["nb", "Ved sjøen", "På fjellet"],
    ]);
    const kinds = await t.run((ctx) => ctx.db.query("question_answer_kinds").collect());
    expect(kinds.map((row) => row.answer_kind).sort()).toEqual(["either_or", "text"]);
  });

  test("rejects missing labels, labels without either_or, and either_or with another kind", async () => {
    const t = newTest();
    const missing = withOptions({
      localizations: {
        en: { prompt: "Sea or mountains?", short_prompt: "Sea or mountains", option_a: "By the sea" },
        nb: { prompt: "Sjø eller fjell?", short_prompt: "Sjø eller fjell", option_a: "Ved sjøen", option_b: "På fjellet" },
      },
    });
    const tooLong = withOptions({
      localizations: {
        en: { prompt: "Sea or mountains?", short_prompt: "Sea or mountains", option_a: "x".repeat(41), option_b: "In the mountains" },
        nb: { prompt: "Sjø eller fjell?", short_prompt: "Sjø eller fjell", option_a: "Ved sjøen", option_b: "På fjellet" },
      },
    });
    const extra = withOptions({ answer_kinds: ["text"] });
    const mixed = withOptions({ answer_kinds: ["either_or", "photo"] });
    const result = await sync(
      t,
      [
        question("missing_label", { versions: [missing] }),
        question("long_label", { versions: [tooLong] }),
        question("extra_labels", { versions: [extra] }),
        question("mixed_kinds", { versions: [mixed] }),
      ],
      true,
    );
    expect(result.applied).toBe(false);
    expect(result.errors).toEqual([
      "system/missing_label/v001 needs option_a and option_b of 1-40 characters in en",
      "system/long_label/v001 needs option_a and option_b of 1-40 characters in en",
      "system/extra_labels/v001 has options in en but no either_or answer kind",
      "system/mixed_kinds/v001 combines either_or with a kind other than text",
    ]);
    expect(await t.run((ctx) => ctx.db.query("questions").collect())).toEqual([]);
  });

  test("a changed label is drift and needs a new version", async () => {
    const t = newTest();
    await sync(t, [question("sea_or_mountains", { versions: [withOptions()] })], true);
    const changed = withOptions({
      localizations: {
        en: { prompt: "Sea or mountains?", short_prompt: "Sea or mountains", option_a: "The sea", option_b: "In the mountains" },
        nb: { prompt: "Sjø eller fjell?", short_prompt: "Sjø eller fjell", option_a: "Ved sjøen", option_b: "På fjellet" },
      },
    });
    const result = await sync(t, [question("sea_or_mountains", { versions: [changed] })], false);
    expect(result.errors).toEqual([
      "system/sea_or_mountains/v001/en differs; create a new version instead of editing an existing one",
    ]);
  });
});
