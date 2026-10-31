import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { readZip } from "./dataExport.testHelpers";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op, setMediaEnv, uploadAsset } from "./media.testing";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => vi.useRealTimers());

async function drawing(t: TestConvex, couple: TestCouple, author: TestUser, game: string, parent: string,
  purpose: "game_drawing_payload" | "exquisite_corpse_drawing" | "exquisite_corpse_strip", text?: string) {
  return await uploadAsset(t, author, {
    kind: purpose === "game_drawing_payload" ? "game_move" : "exquisite_corpse_part",
    purpose, mediaType: "drawing_payload", extension: "pkdrawing", mime: "application/octet-stream",
    parentId: parent, coupleId: couple.coupleId, gameId: game, accessibilityText: text,
  });
}

async function drawRound() {
  const t = newTest();
  const couple = await createCouple(t);
  await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
  const { game_id } = await couple.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
  const roundId = newUuid();
  await couple.first.as.mutation(api.drawAndGuess.pick_draw_word, {
    ...op(), p_game_id: game_id, p_round_id: roundId, p_choice: "custom", p_custom_word: "giraffe", p_word_id: null,
  });
  const text = "A yellow outline with a long neck, four legs and brown spots.";
  const asset = await drawing(t, couple, couple.first, game_id, roundId, "game_drawing_payload", text);
  return { t, couple, gameId: game_id, roundId, asset, text };
}

async function creature() {
  const t = newTest();
  const couple = await createCouple(t);
  await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
  const { game_id } = await couple.first.as.mutation(api.exquisiteCorpse.ensure_exquisite_corpse_game, {});
  return { t, couple, gameId: game_id, figureId: newUuid() };
}

async function part(s: Awaited<ReturnType<typeof creature>>, index: 0 | 1 | 2, text: string) {
  const author = index === 1 ? s.couple.second : s.couple.first;
  const id = newUuid();
  const full = await drawing(s.t, s.couple, author, s.gameId, id, "exquisite_corpse_drawing", text);
  const strip = index < 2 ? await drawing(s.t, s.couple, author, s.gameId, id, "exquisite_corpse_strip") : undefined;
  await author.as.mutation(api.exquisiteCorpse.submit_exquisite_corpse_part, {
    ...op(), p_game_id: s.gameId, p_figure_id: s.figureId, p_part_id: id, p_part_index: index,
    p_drawing_media_asset_id: full.assetId, ...(strip ? { p_strip_media_asset_id: strip.assetId } : {}),
  });
  return { id, full, strip, author };
}

test("Draw & Guess shares authored clue text only after committing its full drawing", async () => {
  const s = await drawRound();
  expect((await s.couple.second.as.query(api.drawAndGuess.get_draw_and_guess, {})).current_round?.drawing_accessibility_text).toBeNull();
  expect((await failure(s.couple.second.as.mutation(api.media.get_media_signed_url,
    { p_media_asset_id: s.asset.assetId }))).code).toBe("42501");
  await s.couple.first.as.mutation(api.drawAndGuess.submit_drawing,
    { ...op(), p_round_id: s.roundId, p_media_asset_id: s.asset.assetId });
  const visible = await s.couple.second.as.query(api.drawAndGuess.get_draw_and_guess, {});
  expect(visible.current_round?.drawing_accessibility_text).toBe(s.text);
  expect(visible.current_round?.drawing_accessibility_text).not.toContain("giraffe");
  await s.couple.second.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: s.roundId });
  expect((await s.couple.second.as.query(api.drawAndGuess.get_draw_and_guess_history_round,
    { p_round_id: s.roundId }))?.drawing_accessibility_text).toBe(s.text);
});

test("Draw & Guess description corrections require the owner, access and a live full drawing", async () => {
  const s = await drawRound();
  await s.couple.first.as.mutation(api.drawAndGuess.submit_drawing,
    { ...op(), p_round_id: s.roundId, p_media_asset_id: s.asset.assetId });
  const request = { ...op(), p_target: { kind: "draw_and_guess" as const, round_id: s.roundId }, p_text: "Two oval ears above the outline." };
  const outsider = await createSignedInUser(s.t);
  for (const user of [outsider, s.couple.second]) {
    expect((await failure(user.as.mutation(api.media.update_accessibility_text, request))).code).toBe("42501");
  }
  const before = (await s.couple.first.as.query(api.drawAndGuess.get_draw_and_guess, {})).current_round;
  await s.couple.first.as.mutation(api.media.update_accessibility_text, request);
  const after = (await s.couple.second.as.query(api.drawAndGuess.get_draw_and_guess, {})).current_round;
  expect(after?.drawing_accessibility_text).toBe(request.p_text);
  expect(after?.word).toBe(before?.word);
  expect(after?.state).toBe(before?.state);
  await s.t.run(async ctx => {
    const asset = await ctx.db.query("media_assets").withIndex("by_uuid", q => q.eq("id", s.asset.assetId)).unique();
    await ctx.db.patch(asset!._id, { deleted_at: new Date().toISOString() });
  });
  expect((await failure(s.couple.first.as.mutation(api.media.update_accessibility_text, request))).code).toBe("42501");
});

test("Odd Creatures full descriptions never accompany an unfinished fold strip", async () => {
  const s = await creature();
  const head = await part(s, 0, "A hidden smiling head with three green eyes.");
  for (const user of [s.couple.first, s.couple.second]) {
    const view = await user.as.query(api.exquisiteCorpse.get_exquisite_corpse, {});
    expect(view.current_figure?.parts[0].drawing_accessibility_text).toBeNull();
  }
  const strip = await s.couple.second.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: head.strip!.assetId });
  expect(strip[0]).not.toHaveProperty("accessibility_text");
  expect(JSON.stringify(strip)).not.toContain("three green eyes");
  expect((await failure(s.couple.second.as.mutation(api.media.get_media_signed_url,
    { p_media_asset_id: head.full.assetId }))).code).toBe("42501");
  await part(s, 1, "A square purple body with two arms.");
  await part(s, 2, "Two blue legs wearing boots.");
  const revealed = await s.couple.second.as.query(api.exquisiteCorpse.get_exquisite_corpse, {});
  const figure = revealed.recent_figures.find(f => f.id === s.figureId) ?? revealed.current_figure;
  expect(figure?.parts.map(p => p.drawing_accessibility_text)).toEqual([
    "A hidden smiling head with three green eyes.", "A square purple body with two arms.", "Two blue legs wearing boots.",
  ]);
});

test("Odd Creatures rejects full descriptions attached to readable strip assets", async () => {
  const s = await creature();
  expect((await failure(drawing(s.t, s.couple, s.couple.first, s.gameId, newUuid(),
    "exquisite_corpse_strip", "Secret full head"))).code).toBe("23514");
});

test("Odd Creatures correction is author-only and remains hidden until final reveal", async () => {
  const s = await creature();
  const head = await part(s, 0, "Original hidden head.");
  const request = { ...op(), p_target: { kind: "exquisite_corpse" as const, part_id: head.id }, p_text: "A round head with four eyes." };
  const outsider = await createSignedInUser(s.t);
  for (const user of [outsider, s.couple.second]) {
    expect((await failure(user.as.mutation(api.media.update_accessibility_text, request))).code).toBe("42501");
  }
  await s.couple.first.as.mutation(api.media.update_accessibility_text, request);
  expect((await s.couple.second.as.query(api.exquisiteCorpse.get_exquisite_corpse, {}))
    .current_figure?.parts[0].drawing_accessibility_text).toBeNull();
  await endCouple(s.t, s.couple.coupleId, s.couple.first.userId);
  expect((await failure(s.couple.first.as.mutation(api.media.update_accessibility_text, request))).code).toBe("42501");
});

test("An unfinished Odd Creatures export contains only the requester's authored media alternatives", async () => {
  const s = await creature();
  const hidden = "Private head description not visible through a folded strip.";
  await part(s, 0, hidden);
  const owner = await s.t.query(internal.dataExport.export_rows,
    { user_id: s.couple.first.userId, table: "media_assets", cursor: null });
  const partner = await s.t.query(internal.dataExport.export_rows,
    { user_id: s.couple.second.userId, table: "media_assets", cursor: null });
  expect(JSON.stringify(owner.rows)).toContain(hidden);
  expect(JSON.stringify(partner.rows)).not.toContain(hidden);
  const partnerParts = await s.t.query(internal.dataExport.export_rows,
    { user_id: s.couple.second.userId, table: "exquisite_corpse_parts", scope_value: s.couple.coupleId, cursor: null });
  expect(partnerParts.rows).toEqual([]);
});

test("The real export archive does not leak an unfinished partner part description", async () => {
  vi.useRealTimers();
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
  const s = await creature();
  const hidden = "Only the author may export this unfinished four-eyed head.";
  await part(s, 0, hidden);
  async function exportedText(user: TestUser) {
    await user.as.mutation(api.dataExport.request_data_export, { p_include_files: false, p_language: "en" });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    const status = await user.as.query(api.dataExportStatus.get_data_export, {});
    expect(status?.status).toBe("ready");
    const links = await user.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: status!.id });
    let text = "";
    for (const link of links) {
      const url = new URL(link.url);
      const response = await s.t.fetch(`${url.pathname}${url.search}`);
      expect(response.status).toBe(200);
      const zip = await readZip(new Uint8Array(await response.arrayBuffer()));
      text += [...zip.values()].map(data => new TextDecoder().decode(data)).join("\n");
    }
    return text;
  }
  expect(await exportedText(s.couple.first)).toContain(hidden);
  expect(await exportedText(s.couple.second)).not.toContain(hidden);
});

test("Odd Creatures cannot edit metadata after the part reference is removed", async () => {
  const s = await creature();
  const head = await part(s, 0, "A head.");
  await s.t.run(async ctx => {
    const stored = await ctx.db.query("exquisite_corpse_parts").withIndex("by_uuid", q => q.eq("id", head.id)).unique();
    await ctx.db.delete(stored!._id);
  });
  expect((await failure(s.couple.first.as.mutation(api.media.update_accessibility_text, {
    ...op(), p_target: { kind: "exquisite_corpse", part_id: head.id }, p_text: "A changed head.",
  }))).code).toBe("42501");
});
