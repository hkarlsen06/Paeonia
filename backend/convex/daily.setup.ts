/// <reference types="vite/client" />
// Shared helpers for the daily and streak tests. The two dots in the file name keep Convex from bundling this file.
import type { Doc } from "./_generated/dataModel";
import { newUuid } from "./lib/ids";
import { nowIso } from "./lib/time";
import type { TestConvex } from "./test.setup";

export type AnswerKind = "text" | "photo" | "voice" | "partner_choice";

export type SeedQuestion = {
  key: string;
  kinds?: AnswerKind[];
  resurfaceable?: boolean;
  months?: number;
};

export type SeededQuestion = { id: string; versionId: string; key: string };

/** `count` text-only questions named q_01, q_02, and so on. */
export function textQuestions(count: number): SeedQuestion[] {
  return Array.from({ length: count }, (_, index) => ({ key: `q_${String(index + 1).padStart(2, "0")}` }));
}

/** Inserts an active system collection with active, ready questions. */
export async function seedCatalog(t: TestConvex, questions: SeedQuestion[]): Promise<SeededQuestion[]> {
  return await t.run(async (ctx) => {
    const now = nowIso();
    const collectionId = newUuid();
    await ctx.db.insert("question_collections", {
      id: collectionId,
      kind: "system",
      status: "active",
      created_at: now,
      updated_at: now,
    });
    const seeded: SeededQuestion[] = [];
    for (const question of questions) {
      const id = newUuid();
      const versionId = newUuid();
      await ctx.db.insert("questions", {
        id,
        collection_id: collectionId,
        key: question.key,
        status: "active",
        resurfaceable: question.resurfaceable ?? true,
        resurface_after_months: question.months ?? 6,
        created_at: now,
        updated_at: now,
      });
      await ctx.db.insert("question_versions", {
        id: versionId,
        question_id: id,
        version_number: 1,
        status: "active",
        active_from: now,
        created_at: now,
      });
      for (const locale of ["en", "nb"] as const) {
        await ctx.db.insert("question_version_localizations", {
          question_version_id: versionId,
          locale,
          prompt: `${question.key} prompt ${locale}`,
          short_prompt: `${question.key} short ${locale}`,
          created_at: now,
          updated_at: now,
        });
      }
      for (const kind of question.kinds ?? ["text"]) {
        await ctx.db.insert("question_answer_kinds", { question_version_id: versionId, answer_kind: kind, created_at: now });
      }
      seeded.push({ id, versionId, key: question.key });
    }
    return seeded;
  });
}

/** The daily questions of the couple `userId` is in, on any day, that nobody skipped, oldest first. */
export async function dailyQuestionsFor(t: TestConvex, userId: string): Promise<Doc<"daily_question_instances">[]> {
  return await t.run(async (ctx) => {
    const member = await ctx.db
      .query("couple_members")
      .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId).eq("status", "active"))
      .first();
    if (!member) return [];
    const rows = await ctx.db
      .query("daily_question_instances")
      .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", member.couple_id))
      .collect();
    return rows
      .filter((row) => row.couple_day_id !== undefined && row.status === "active")
      .sort((a, b) => a._creationTime - b._creationTime);
  });
}

/** The newest daily question of the couple `userId` is in. */
export async function currentQuestionFor(t: TestConvex, userId: string): Promise<Doc<"daily_question_instances">> {
  const rows = await dailyQuestionsFor(t, userId);
  if (rows.length === 0) throw new Error("the couple has no daily question yet");
  return rows[rows.length - 1];
}

/** Inserts a finalized image or voice asset reserved for a daily answer. */
export async function insertAnswerAsset(
  t: TestConvex,
  options: { ownerUserId: string; coupleId: string; answerId: string; mediaType?: "image" | "voice" },
): Promise<string> {
  return await t.run(async (ctx) => {
    const id = newUuid();
    const now = nowIso();
    const mediaType = options.mediaType ?? "image";
    await ctx.db.insert("media_assets", {
      id,
      owner_user_id: options.ownerUserId,
      couple_id: options.coupleId,
      reserved_parent_kind: "daily_answer_media",
      reserved_parent_id: options.answerId,
      reserved_by_client_operation_id: newUuid(),
      bucket: "couple-media",
      storage_path: `${options.coupleId}/${id}`,
      media_type: mediaType,
      upload_purpose: mediaType === "image" ? "daily_answer_media" : "voice_note",
      expected_media_type: mediaType,
      expected_bucket: "couple-media",
      upload_status: "finalized",
      upload_expires_at: now,
      upload_finalized_at: now,
      moderation_status: "visible",
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      created_at: now,
      updated_at: now,
    });
    return id;
  });
}
