import { v, type Infer } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import subscriptionProducts from "../seed/subscription_products.json";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, omitNulls, withUpdatedAt } from "./lib/db";
import { checkViolation, fail } from "./lib/errors";
import { newUuid, timestampArg } from "./lib/ids";
import { nowIso } from "./lib/time";
import { literals } from "./lib/validators";

/**
 * Question catalog sync. `scripts/sync-question-catalog` parses backend/questions
 * and calls `catalog:sync_catalog` with `npx convex run`. Catalog rows are content,
 * not schema, so nothing else writes them.
 */

const answerKind = literals("text", "photo", "voice", "partner_choice");
const localization = v.object({ prompt: v.string(), short_prompt: v.string() });
const optionalTimestamp = v.optional(v.union(v.null(), v.string()));

const versionPayload = v.object({
  number: v.number(),
  status: literals("draft", "active", "retired"),
  active_from: optionalTimestamp,
  retired_at: optionalTimestamp,
  answer_kinds: v.array(answerKind),
  localizations: v.object({ en: localization, nb: localization }),
});

const questionPayload = v.object({
  collection: literals("system", "custom", "mini_game"),
  key: v.string(),
  status: literals("draft", "active", "retired", "archived"),
  resurfaceable: v.boolean(),
  resurface_after_months: v.optional(v.union(v.null(), v.number())),
  versions: v.array(versionPayload),
});

type QuestionPayload = Infer<typeof questionPayload>;
type VersionPayload = Infer<typeof versionPayload>;

const LOCALES = ["en", "nb"] as const;
const NEW_VERSION_HINT = "create a new version instead of editing an existing one";

function versionLabel(question: QuestionPayload, version: VersionPayload): string {
  return `${question.collection}/${question.key}/v${String(version.number).padStart(3, "0")}`;
}

/** The oldest collection of a kind that belongs to no couple and no user. */
async function findCollection(
  ctx: ReaderCtx,
  kind: QuestionPayload["collection"],
): Promise<Doc<"question_collections"> | null> {
  const rows = await ctx.db
    .query("question_collections")
    .withIndex("by_kind_status", (q) => q.eq("kind", kind))
    .collect();
  const scoped = rows.filter((row) => row.couple_id === undefined && row.created_by_user_id === undefined);
  scoped.sort((a, b) => (a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : 0));
  return scoped[0] ?? null;
}

async function findQuestion(ctx: ReaderCtx, collectionId: string, key: string): Promise<Doc<"questions"> | null> {
  return await ctx.db
    .query("questions")
    .withIndex("by_collection_id_key", (q) => q.eq("collection_id", collectionId).eq("key", key))
    .unique();
}

async function findVersion(
  ctx: ReaderCtx,
  questionId: string,
  versionNumber: number,
): Promise<Doc<"question_versions"> | null> {
  return await ctx.db
    .query("question_versions")
    .withIndex("by_question_id_version_number", (q) => q.eq("question_id", questionId).eq("version_number", versionNumber))
    .unique();
}

async function answerKindsOf(ctx: ReaderCtx, versionId: string): Promise<Doc<"question_answer_kinds">[]> {
  return await ctx.db
    .query("question_answer_kinds")
    .withIndex("by_question_version_id_answer_kind", (q) => q.eq("question_version_id", versionId))
    .collect();
}

async function localizationOf(
  ctx: ReaderCtx,
  versionId: string,
  locale: "en" | "nb",
): Promise<Doc<"question_version_localizations"> | null> {
  return await ctx.db
    .query("question_version_localizations")
    .withIndex("by_question_version_id_locale", (q) => q.eq("question_version_id", versionId).eq("locale", locale))
    .unique();
}

// ---- readiness (ports of the deferred assert_active_question_* triggers) ----

/** Port of `internal.assert_active_question_version_ready`. */
async function assertVersionReady(ctx: ReaderCtx, versionId: string): Promise<void> {
  const version = await getByUuid(ctx, "question_versions", versionId);
  if (!version) return;
  const question = await getByUuid(ctx, "questions", version.question_id);
  const collection = question ? await getByUuid(ctx, "question_collections", question.collection_id) : null;
  if (!question || !collection) return;

  const kindCount = (await answerKindsOf(ctx, versionId)).length;
  if (kindCount > 2) {
    fail("23514", "question versions can have at most two answer kinds");
  }
  if (collection.status === "active" && question.status === "active" && version.status === "active") {
    let locales = 0;
    for (const locale of LOCALES) {
      if (await localizationOf(ctx, versionId, locale)) locales += 1;
    }
    if (locales !== 2) {
      fail("23514", "active question versions require en and nb localizations");
    }
    if (kindCount < 1) {
      fail("23514", "active question versions require at least one answer kind");
    }
  }
}

/** Port of `internal.assert_active_question_ready`. */
async function assertQuestionReady(ctx: ReaderCtx, questionId: string): Promise<void> {
  const question = await getByUuid(ctx, "questions", questionId);
  const collection = question ? await getByUuid(ctx, "question_collections", question.collection_id) : null;
  if (!question || !collection) return;
  if (collection.status === "active" && question.status === "active") {
    const versions = await ctx.db
      .query("question_versions")
      .withIndex("by_question_id_status", (q) => q.eq("question_id", questionId).eq("status", "active"))
      .collect();
    const active = versions.sort((a, b) => b.version_number - a.version_number)[0];
    if (!active) {
      fail("23514", "active questions require an active version");
    }
    await assertVersionReady(ctx, active.id);
  }
}

/** Port of `internal.assert_active_question_collection_ready`. */
async function assertCollectionReady(ctx: ReaderCtx, collectionId: string): Promise<void> {
  const collection = await getByUuid(ctx, "question_collections", collectionId);
  if (!collection || collection.status !== "active") return;
  const active = await ctx.db
    .query("questions")
    .withIndex("by_collection_id_status", (q) => q.eq("collection_id", collectionId).eq("status", "active"))
    .collect();
  if (active.length < 1) {
    fail("23514", "active collections require active questions");
  }
  for (const question of active) {
    await assertQuestionReady(ctx, question.id);
  }
}

// ---- compare (dry run) ----

async function compareCatalog(
  ctx: ReaderCtx,
  questions: QuestionPayload[],
): Promise<{ changes: string[]; errors: string[] }> {
  const changes: string[] = [];
  const errors: string[] = [];
  for (const question of questions) {
    const name = `${question.collection}/${question.key}`;
    const collection = await findCollection(ctx, question.collection);
    const remoteQuestion = collection ? await findQuestion(ctx, collection.id, question.key) : null;
    const remoteVersions = remoteQuestion
      ? await ctx.db
          .query("question_versions")
          .withIndex("by_question_id_version_number", (q) => q.eq("question_id", remoteQuestion.id))
          .collect()
      : [];
    if (!remoteQuestion || remoteVersions.length === 0) {
      changes.push(`new question ${name}`);
      continue;
    }
    if (remoteQuestion.status !== question.status) {
      changes.push(`status update for ${name}`);
    }
    if (
      remoteQuestion.resurfaceable !== question.resurfaceable ||
      (remoteQuestion.resurface_after_months ?? null) !== (question.resurface_after_months ?? null)
    ) {
      changes.push(`resurfacing update for ${name}`);
    }
    for (const version of question.versions) {
      const label = versionLabel(question, version);
      const remote = remoteVersions.find((row) => row.version_number === version.number);
      if (!remote) {
        changes.push(`new version ${label}`);
        continue;
      }
      if (remote.status !== version.status) {
        changes.push(`status update for ${label}`);
      }
      const remoteKinds = (await answerKindsOf(ctx, remote.id)).map((row) => row.answer_kind).sort();
      const kinds = [...version.answer_kinds].sort();
      if (remoteKinds.length !== kinds.length || remoteKinds.some((kind, index) => kind !== kinds[index])) {
        errors.push(`${label} answer_kinds differ; ${NEW_VERSION_HINT}`);
      }
      for (const locale of LOCALES) {
        const remoteLocalization = await localizationOf(ctx, remote.id, locale);
        if (!remoteLocalization) {
          changes.push(`missing locale ${locale} for ${label}`);
        } else if (
          remoteLocalization.prompt !== version.localizations[locale].prompt ||
          remoteLocalization.short_prompt !== version.localizations[locale].short_prompt
        ) {
          errors.push(`${label}/${locale} differs; ${NEW_VERSION_HINT}`);
        }
      }
    }
  }
  return { changes, errors };
}

// ---- apply ----

function charLength(value: string): number {
  return Array.from(value).length;
}

function assertLocalization(prompt: string, shortPrompt: string): void {
  const promptLength = charLength(prompt.replace(/^ +| +$/g, ""));
  if (promptLength < 3 || promptLength > 500) {
    checkViolation("question_version_localizations", "question_version_localizations_prompt_check");
  }
  const shortLength = charLength(shortPrompt.replace(/^ +| +$/g, ""));
  if (shortLength < 3 || shortLength > 160) {
    checkViolation("question_version_localizations", "question_version_localizations_short_prompt_check");
  }
}

/** Writes one question and its versions. Returns the collection id so the caller can check collection readiness once. */
async function applyQuestion(ctx: WriterCtx, question: QuestionPayload): Promise<string> {
  if (!/^[a-z][a-z0-9_]{2,120}$/.test(question.key)) {
    checkViolation("questions", "questions_key_check");
  }
  const months = question.resurface_after_months ?? undefined;
  if (months !== undefined && (!Number.isInteger(months) || months < 1 || months > 60)) {
    checkViolation("questions", "questions_resurface_after_months_check");
  }
  if (question.resurfaceable && months === undefined) {
    checkViolation("questions", "questions_resurface_after_months_check");
  }

  let collection = await findCollection(ctx, question.collection);
  if (!collection) {
    const now = nowIso();
    const id = newUuid();
    await ctx.db.insert("question_collections", {
      id,
      kind: question.collection,
      status: "draft",
      created_at: now,
      updated_at: now,
    });
    collection = (await getByUuid(ctx, "question_collections", id))!;
  }

  let target = await findQuestion(ctx, collection.id, question.key);
  if (!target) {
    const now = nowIso();
    const id = newUuid();
    await ctx.db.insert("questions", {
      id,
      collection_id: collection.id,
      key: question.key,
      status: "draft",
      resurfaceable: question.resurfaceable,
      resurface_after_months: months,
      created_at: now,
      updated_at: now,
    });
    target = (await getByUuid(ctx, "questions", id))!;
  } else if (target.resurfaceable !== question.resurfaceable || target.resurface_after_months !== months) {
    await ctx.db.patch(
      target._id,
      withUpdatedAt({ resurfaceable: question.resurfaceable, resurface_after_months: months }),
    );
  }

  for (const version of question.versions) {
    let row = await findVersion(ctx, target.id, version.number);
    if (!row) {
      const id = newUuid();
      const now = nowIso();
      await ctx.db.insert("question_versions", {
        id,
        question_id: target.id,
        version_number: version.number,
        status: "draft",
        active_from: version.active_from ? timestampArg(version.active_from) : now,
        created_at: now,
      });
      row = (await getByUuid(ctx, "question_versions", id))!;
    }

    for (const locale of LOCALES) {
      if (!(await localizationOf(ctx, row.id, locale))) {
        const { prompt, short_prompt } = version.localizations[locale];
        assertLocalization(prompt, short_prompt);
        const now = nowIso();
        await ctx.db.insert("question_version_localizations", {
          question_version_id: row.id,
          locale,
          prompt,
          short_prompt,
          created_at: now,
          updated_at: now,
        });
      }
    }
    const existingKinds = new Set((await answerKindsOf(ctx, row.id)).map((item) => item.answer_kind));
    for (const kind of version.answer_kinds) {
      if (!existingKinds.has(kind)) {
        await ctx.db.insert("question_answer_kinds", {
          question_version_id: row.id,
          answer_kind: kind,
          created_at: nowIso(),
        });
      }
    }

    if (version.status === "active") {
      const others = await ctx.db
        .query("question_versions")
        .withIndex("by_question_id_status", (q) => q.eq("question_id", target.id).eq("status", "active"))
        .collect();
      for (const other of others) {
        if (other.id !== row.id) {
          await ctx.db.patch(other._id, { status: "retired", retired_at: other.retired_at ?? nowIso() });
        }
      }
      await ctx.db.patch(row._id, { status: "active", retired_at: undefined });
    } else if (version.status === "retired") {
      await ctx.db.patch(row._id, {
        status: "retired",
        retired_at: row.retired_at ?? (version.retired_at ? timestampArg(version.retired_at) : nowIso()),
      });
    } else {
      if (row.retired_at !== undefined) {
        checkViolation("question_versions", "question_versions_retired_state_check");
      }
      await ctx.db.patch(row._id, { status: version.status });
    }
  }

  if (target.status !== question.status) {
    await ctx.db.patch(target._id, withUpdatedAt({ status: question.status }));
  }
  if (collection.status === "draft" && question.status === "active") {
    await ctx.db.patch(collection._id, withUpdatedAt({ status: "active" }));
  }
  await assertQuestionReady(ctx, target.id);
  return collection.id;
}

/**
 * Compares the parsed catalog with the deployment and, with `apply`, writes the
 * differences. An existing version's localizations and answer kinds never change:
 * a mismatch comes back in `errors` and nothing is written.
 */
export const sync_catalog = internalMutation({
  args: { questions: v.array(questionPayload), apply: v.boolean() },
  handler: async (ctx, args) => {
    const { changes, errors } = await compareCatalog(ctx, args.questions);
    if (errors.length > 0 || !args.apply) {
      return { changes, errors, applied: false };
    }
    const collectionIds = new Set<string>();
    for (const question of args.questions) {
      collectionIds.add(await applyQuestion(ctx, question));
    }
    for (const collectionId of collectionIds) {
      await assertCollectionReady(ctx, collectionId);
    }
    return { changes, errors, applied: true };
  },
});

/** Loads `backend/seed/subscription_products.json`. Existing products keep their id and are updated in place. */
export const seed_subscription_products = internalMutation({
  args: {},
  handler: async (ctx) => {
    for (const raw of subscriptionProducts) {
      const row = omitNulls(raw) as Omit<Doc<"subscription_products">, "_id" | "_creationTime">;
      const existing = await ctx.db
        .query("subscription_products")
        .withIndex("by_apple_product_id", (q) => q.eq("apple_product_id", row.apple_product_id))
        .unique();
      if (existing) {
        await ctx.db.patch(
          existing._id,
          withUpdatedAt({ kind: row.kind, billing_period: row.billing_period, is_active: row.is_active }),
        );
      } else {
        await ctx.db.insert("subscription_products", row);
      }
    }
    return subscriptionProducts.length;
  },
});
