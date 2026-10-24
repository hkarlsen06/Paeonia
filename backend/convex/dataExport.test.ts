import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { answeredRound, seedQuestion } from "./dailyChat.setup";
import { jsonOf, readZip, textOf } from "./dataExport.testHelpers";
import { newUuid } from "./lib/ids";
import { deliverDuePushes } from "./push.testing";
import { failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-21T08:30:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
  delete process.env.PAEONIA_EXPORT_PART_LIMIT_BYTES;
  delete process.env.PAEONIA_EXPORT_CHUNK_BYTES;
  delete process.env.PAEONIA_EXPORT_COLLECT_BUDGET_MS;
});

const run = (t: TestConvex) => t.finishAllScheduledFunctions(vi.runAllTimers);
const pathOf = (url: string) => {
  const parsed = new URL(url);
  return `${parsed.pathname}${parsed.search}`;
};

async function requestExport(t: TestConvex, user: TestUser, includeFiles = true) {
  const requested = await user.as.mutation(api.dataExport.request_data_export, {
    p_include_files: includeFiles,
    p_language: "en",
  });
  await run(t);
  return { requested, status: (await user.as.query(api.dataExportStatus.get_data_export, {}))! };
}

/** Downloads every zip of a ready export through its signed links, like the app does. */
async function downloadZips(t: TestConvex, user: TestUser, exportId: string) {
  const links = await user.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: exportId });
  const zips: Map<string, Uint8Array>[] = [];
  for (const link of links) {
    const response = await t.fetch(pathOf(link.url));
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Disposition")).toContain(link.file_name);
    zips.push(await readZip(new Uint8Array(await response.arrayBuffer())));
  }
  return { links, zips };
}

const allJsonText = (zips: Map<string, Uint8Array>[]) =>
  zips
    .flatMap((zip) => [...zip.entries()])
    .filter(([name]) => name.endsWith(".json") || name.endsWith(".md"))
    .map(([, data]) => new TextDecoder().decode(data))
    .join("\n");

type Content = {
  memoryId: string;
  photoBytes: Uint8Array;
  assetId: string;
};

/** A couple with a memory, photos, chat, a daily answer, a location and a device for each partner. */
async function fillCouple(t: TestConvex, couple: TestCouple, marker: string): Promise<Content & { partnerPhotoBytes: Uint8Array }> {
  const { first, second } = couple;
  const photoBytes = new TextEncoder().encode(`${marker}-first-photo`);
  const partnerPhotoBytes = new TextEncoder().encode(`${marker}-second-photo`);
  const memoryId = newUuid();
  const mine = await uploadAsset(t, first, { ...photo(couple.coupleId), parentId: newUuid(), bytes: photoBytes });
  await first.as.mutation(api.memories.create_memory, {
    ...op(),
    p_memory_id: memoryId,
    p_title: `${marker} memory title`,
    p_memory_date: "2026-10-01",
    p_note_body: `${marker} first note`,
    p_media_asset_ids: [mine.assetId],
  });
  await uploadAsset(t, second, { ...photo(couple.coupleId), parentId: newUuid(), bytes: partnerPhotoBytes });
  await second.as.mutation(api.memories.upsert_memory_note, {
    ...op(),
    p_memory_id: memoryId,
    p_body: `${marker} second note`,
  });
  const [thread] = await first.as.mutation(api.threads.create_memory_thread_with_message, {
    ...op(),
    p_memory_id: memoryId,
    p_body: `${marker} first message`,
  });
  await second.as.mutation(api.threads.send_thread_message, {
    ...op(),
    p_thread_id: thread.thread_id,
    p_body: `${marker} second message`,
  });
  const question = await seedQuestion(t);
  await answeredRound(t, couple, question, {
    texts: { [first.userId]: `${marker} first answer`, [second.userId]: `${marker} second answer` },
  });
  for (const [user, latitude] of [
    [first, 59.1],
    [second, 61.2],
  ] as const) {
    await addDevice(t, user.userId, { token: `${marker}-device-${latitude}` });
    await t.run((ctx) =>
      ctx.db.insert("latest_partner_locations", {
        couple_id: couple.coupleId,
        user_id: user.userId,
        latitude,
        longitude: 10.5,
        captured_at: new Date().toISOString(),
        received_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        source: "foreground_open",
        client_operation_id: newUuid(),
        client_id: newUuid(),
        client_sequence: 1,
      }),
    );
  }
  return { memoryId, photoBytes, partnerPhotoBytes, assetId: mine.assetId };
}

describe("Download my data", () => {
  test("holds the person's own data and the shared things, and nothing of the partner's or another couple's", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const other = await createCouple(t);
    const mine = await fillCouple(t, couple, "AAA");
    const theirs = await fillCouple(t, other, "ZZZ");

    // A field added to an existing table needs no change to the export.
    await t.run((ctx) =>
      ctx.db.insert("location_sharing_preferences", {
        couple_id: couple.coupleId,
        user_id: couple.first.userId,
        is_enabled: true,
        source: "settings_toggle",
        updates_while_closed: false,
        paused_until: "2026-10-21T20:00:00.000Z",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }),
    );

    const { requested, status } = await requestExport(t, couple.first);
    expect(requested.status).toBe("preparing");
    expect(status).toMatchObject({ id: requested.id, status: "ready", progress: 1, part_count: 1, file_count: 1, skipped_file_count: 0 });

    const { zips } = await downloadZips(t, couple.first, status.id);
    expect(zips).toHaveLength(1);
    const zip = zips[0]!;
    const text = allJsonText(zips);

    // Mine, in full.
    expect(text).toContain("AAA first message");
    expect(text).toContain("AAA first note");
    expect(text).toContain("AAA first answer");
    expect(jsonOf(zip, "daily-questions/question_version_localizations.json")).toHaveLength(2);
    expect(text).toMatch(/q_[0-9a-f]{8} prompt en/);
    expect(jsonOf(zip, "account/users.json")).toMatchObject([{ id: couple.first.userId }]);
    expect(jsonOf(zip, "chat/thread_messages.json")).toHaveLength(1);
    expect(jsonOf(zip, "location/location_sharing_preferences.json")).toMatchObject([{ paused_until: "2026-10-21T20:00:00.000Z" }]);
    expect(jsonOf(zip, "location/latest_partner_locations.json")).toMatchObject([{ user_id: couple.first.userId, latitude: 59.1 }]);
    // Shared by both, while they are together.
    expect(text).toContain("AAA memory title");
    expect(jsonOf(zip, "relationship/couples.json")).toMatchObject([{ id: couple.coupleId }]);
    // My photo is in the archive, byte for byte, and the media list points to it.
    const files = [...zip.keys()].filter((name) => name.startsWith("files/") && !name.endsWith(".json"));
    expect(files).toHaveLength(1);
    const mediaRows = jsonOf<{ id: string; file: string | null; owner_user_id: string }[]>(zip, "files/media_assets.json");
    expect(mediaRows.every((row) => row.owner_user_id === couple.first.userId)).toBe(true);
    const photoRow = mediaRows.find((row) => row.id === mine.assetId)!;
    expect(zip.get(photoRow.file!)).toEqual(mine.photoBytes);

    // Not the partner's text, files, location, devices or secrets.
    expect(text).not.toContain("AAA second message");
    expect(text).not.toContain("AAA second note");
    expect(text).not.toContain("AAA second answer");
    expect(text).not.toContain("61.2");
    expect(text).not.toContain("AAA-device");
    expect(text).not.toContain("push_token");
    expect([...zip.values()].some((data) => new TextDecoder().decode(data) === new TextDecoder().decode(mine.partnerPhotoBytes))).toBe(false);

    // Nothing at all from another couple.
    for (const marker of ["ZZZ", other.coupleId, other.pairId, other.first.userId, other.second.userId, theirs.memoryId, theirs.assetId]) {
      expect(text, `leaked ${marker}`).not.toContain(marker);
    }
    expect([...zip.values()].some((data) => new TextDecoder().decode(data) === new TextDecoder().decode(theirs.photoBytes))).toBe(false);

    // The README and the manifest explain it.
    expect(textOf(zip, "README.md")).toContain("Datatilsynet");
    const manifest = jsonOf<{ files: { path: string }[]; not_included: { table: string; reason: string }[] }>(zip, "manifest.json");
    expect(manifest.files.map((file) => file.path)).toContain("chat/thread_messages.json");
    expect(manifest.not_included.map((entry) => entry.table)).toContain("client_operations");
  });

  test("a person without a partner or a subscription can download their data", async () => {
    const t = newTest();
    const alone = await createSignedInUser(t, { name: "Alone" });
    const { status } = await requestExport(t, alone);
    expect(status.status).toBe("ready");
    const { zips } = await downloadZips(t, alone, status.id);
    expect(jsonOf(zips[0]!, "account/users.json")).toMatchObject([{ id: alone.userId }]);
    expect(jsonOf(zips[0]!, "account/profiles.json")).toHaveLength(1);
  });

  test("leaving the files out gives data only", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await fillCouple(t, couple, "AAA");
    const { status } = await requestExport(t, couple.first, false);
    const { zips } = await downloadZips(t, couple.first, status.id);
    expect([...zips[0]!.keys()].filter((name) => /^files\/.+\/.+/.test(name))).toEqual([]);
    expect(jsonOf<{ file: string | null }[]>(zips[0]!, "files/media_assets.json").every((row) => row.file === null)).toBe(true);
    expect(textOf(zips[0]!, "README.md")).toContain("You chose to leave out");
  });

  test("a relationship that ended keeps only the person's own things", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await fillCouple(t, couple, "AAA");
    await t.run(async (ctx) => {
      const member = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.coupleId).eq("user_id", couple.first.userId))
        .unique();
      await ctx.db.patch(member!._id, { status: "left" });
      const row = await ctx.db.query("couples").withIndex("by_uuid", (q) => q.eq("id", couple.coupleId)).unique();
      await ctx.db.patch(row!._id, { status: "ended" });
    });
    const { status } = await requestExport(t, couple.first);
    const { zips } = await downloadZips(t, couple.first, status.id);
    const text = allJsonText(zips);
    expect(text).toContain("AAA first message");
    expect(text).toContain("AAA first note");
    expect(text).not.toContain("AAA memory title");
    expect(text).not.toContain("AAA second");
  });

  test("a large download is split into zip files that all open and hold every file once", async () => {
    process.env.PAEONIA_EXPORT_PART_LIMIT_BYTES = "150";
    const t = newTest();
    const couple = await createCouple(t);
    const bytes = [1, 2, 3].map((n) => new Uint8Array(100).fill(n));
    for (const data of bytes) await uploadAsset(t, couple.first, { ...photo(couple.coupleId), bytes: data });
    const { status } = await requestExport(t, couple.first);
    // With a limit this small, every data file and every photo gets a zip of its own.
    expect(status.part_count).toBeGreaterThan(4);
    const { links, zips } = await downloadZips(t, couple.first, status.id);
    expect(links.map((link) => link.part_number)).toEqual(links.map((_, index) => index + 1));
    expect(links[1]!.file_name).toMatch(new RegExp(`-part-2-of-${status.part_count}\\.zip$`));
    const found = zips.flatMap((zip) => [...zip.entries()].filter(([name]) => name.startsWith("files/") && !name.endsWith(".json")));
    expect(found).toHaveLength(3);
    expect(found.map(([, data]) => data[0]).sort()).toEqual([1, 2, 3]);
    expect(zips[0]!.has("README.md")).toBe(true);
    expect(zips.slice(1).some((zip) => zip.has("README.md"))).toBe(false);
    expect(textOf(zips[0]!, "README.md")).toContain(`-part-${status.part_count}-of-${status.part_count}.zip`);
    // Every data file is in exactly one zip, and the manifest says which.
    const names = zips.flatMap((zip) => [...zip.keys()]);
    expect(new Set(names).size).toBe(names.length);
    const manifest = jsonOf<{ files: { path: string; zip_file: string }[] }>(zips[0]!, "manifest.json");
    for (const file of manifest.files) {
      const zipIndex = links.findIndex((link) => link.file_name === file.zip_file);
      expect(zips[zipIndex]!.has(file.path), file.path).toBe(true);
    }
  });

  test("a big table is cut into numbered data files, across parts and across build actions", async () => {
    process.env.PAEONIA_EXPORT_CHUNK_BYTES = "500";
    process.env.PAEONIA_EXPORT_PART_LIMIT_BYTES = "2000000";
    // Every table is its own action.
    process.env.PAEONIA_EXPORT_COLLECT_BUDGET_MS = "0";
    const t = newTest();
    const couple = await createCouple(t);
    const content = await fillCouple(t, couple, "AAA");
    const [thread] = await t.run((ctx) => ctx.db.query("conversation_threads").collect());
    for (let n = 1; n <= 5; n += 1) {
      await couple.first.as.mutation(api.threads.send_thread_message, {
        ...op(),
        p_thread_id: thread!.id,
        p_body: `AAA bulk message ${n} ${"x".repeat(300)}`,
      });
    }
    const { status } = await requestExport(t, couple.first);
    expect(status.status).toBe("ready");
    const { zips } = await downloadZips(t, couple.first, status.id);
    const names = zips.flatMap((zip) => [...zip.keys()]);
    expect(new Set(names).size).toBe(names.length);
    const messageFiles = names.filter((name) => /^chat\/thread_messages(-\d{3})?\.json$/.test(name)).sort();
    expect(messageFiles.length).toBeGreaterThan(1);
    expect(messageFiles.every((name) => /-\d{3}\.json$/.test(name))).toBe(true);
    const rows = messageFiles.flatMap((name) => {
      const zip = zips.find((candidate) => candidate.has(name))!;
      return jsonOf<{ body: string }[]>(zip, name);
    });
    expect(rows).toHaveLength(6);
    expect(rows.filter((row) => row.body.startsWith("AAA bulk message"))).toHaveLength(5);
    expect(status.row_count).toBeGreaterThan(rows.length);
    // A table that fits in one file keeps its plain name, and nothing is left waiting in storage.
    expect(names).toContain("relationship/couples.json");
    expect(await t.run((ctx) => ctx.db.query("data_export_chunks").collect())).toHaveLength(0);
    // The photo and its list still match.
    const mediaRows = zips.flatMap((zip) => (zip.has("files/media_assets.json") ? jsonOf<{ id: string; file: string }[]>(zip, "files/media_assets.json") : []));
    const photoRow = mediaRows.find((row) => row.id === content.assetId)!;
    expect(zips.find((zip) => zip.has(photoRow.file))!.get(photoRow.file)).toEqual(content.photoBytes);
  });

  test("a build that fails leaves no data files in storage", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const requested = await couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: false, p_language: "en" });
    await t.action(internal.dataExportBuild.collect_data, { export_id: requested.id, table_index: 0 });
    expect((await t.run((ctx) => ctx.db.system.query("_storage").collect())).length).toBeGreaterThan(0);
    // A second row for part 1 makes the part build fail.
    await t.run(async (ctx) => {
      const [part] = await ctx.db.query("data_export_parts").collect();
      const { _id, _creationTime, ...copy } = part!;
      await ctx.db.insert("data_export_parts", { ...copy, id: newUuid() });
    });
    await t.action(internal.dataExportBuild.build_part, { export_id: requested.id, part_number: 1 });
    expect((await couple.first.as.query(api.dataExportStatus.get_data_export, {}))?.status).toBe("failed");
    expect(await t.run((ctx) => ctx.db.system.query("_storage").collect())).toHaveLength(0);
    expect(await t.run((ctx) => ctx.db.query("data_export_chunks").collect())).toHaveLength(0);
  });

  test("the couple's questions come with the export, and the partner's answers never do", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const both = await seedQuestion(t);
    const partnerOnly = await seedQuestion(t);
    const answeredHere = await answeredRound(t, couple, both, {
      texts: { [couple.first.userId]: "AAA my answer", [couple.second.userId]: "AAA their answer" },
    });
    // A question only the partner has answered so far is the couple's question too.
    const waiting = await answeredRound(t, couple, partnerOnly, {
      answeredBy: [couple.second],
      texts: { [couple.second.userId]: "BBB their answer" },
    });

    const { status } = await requestExport(t, couple.first);
    const { zips } = await downloadZips(t, couple.first, status.id);
    const zip = zips[0]!;
    const instances = jsonOf<{ id: string }[]>(zip, "daily-questions/daily_question_instances.json").map((row) => row.id);
    expect(instances).toEqual(expect.arrayContaining([answeredHere, waiting]));
    const versions = jsonOf<{ question_version_id: string }[]>(zip, "daily-questions/question_version_localizations.json").map((row) => row.question_version_id);
    expect(versions).toEqual(expect.arrayContaining([both.versionId, partnerOnly.versionId]));
    expect(allJsonText(zips)).toContain("AAA my answer");
    expect(allJsonText(zips)).not.toContain("AAA their answer");
    expect(allJsonText(zips)).not.toContain("BBB their answer");
  });

  test("a file that is gone from storage is left out and counted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const gone = await uploadAsset(t, couple.first, photo(couple.coupleId));
    await uploadAsset(t, couple.first, photo(couple.coupleId));
    await t.run((ctx) => ctx.storage.delete(gone.storageId as never));
    const { status } = await requestExport(t, couple.first);
    expect(status).toMatchObject({ status: "ready", file_count: 1, skipped_file_count: 1 });
    const { zips } = await downloadZips(t, couple.first, status.id);
    const rows = jsonOf<{ id: string; file: string | null }[]>(zips[0]!, "files/media_assets.json");
    expect(rows.find((row) => row.id === gone.assetId)?.file).toBeNull();
  });

  test("tells the person with a push when it is ready", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId, { locale: "nb-NO" });
    await addDevice(t, couple.second.userId);
    await requestExport(t, couple.first);
    const rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(rows).toMatchObject([
      {
        recipient_user_id: couple.first.userId,
        kind: "data_export_ready",
        title: "Dataene dine er klare",
        body: "Kopien din er klar til nedlasting.",
        payload: { deeplink: "paeonia://settings/data-export" },
      },
    ]);
    // It passes the send-time checks, and it names no content.
    const delivered = await deliverDuePushes(t);
    expect(delivered).toHaveLength(1);
    expect(delivered[0]).toMatchObject({
      title: "Dataene dine er klare",
      payload: { type: "data_export_ready", deeplink: "paeonia://settings/data-export" },
    });
  });
});

describe("who can ask, download and delete", () => {
  test("a signed-out caller is refused everywhere", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { status } = await requestExport(t, couple.first);
    for (const call of [
      () => t.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" }),
      () => t.query(api.dataExportStatus.get_data_export, {}),
      () => t.mutation(api.dataExport.create_data_export_download_links, { p_export_id: status.id }),
      () => t.mutation(api.dataExport.delete_data_export, { p_export_id: status.id }),
    ]) {
      expect((await failure(call())).code).toBe("42501");
    }
  });

  test("another person cannot see, download or delete someone else's download", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { status } = await requestExport(t, couple.first);
    expect(await couple.second.as.query(api.dataExportStatus.get_data_export, {})).toBeNull();
    expect((await failure(couple.second.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: status.id }))).code).toBe("42501");
    expect(await couple.second.as.mutation(api.dataExport.delete_data_export, { p_export_id: status.id })).toBe(false);
    expect((await couple.first.as.query(api.dataExportStatus.get_data_export, {}))?.status).toBe("ready");
  });

  test("a link works only with its own signature, and only for an hour", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { status } = await requestExport(t, couple.first);
    const [link] = await couple.first.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: status.id });
    const good = pathOf(link!.url);
    expect((await t.fetch(good)).status).toBe(200);
    // Change one character of the signature, and of the part id (which is signed too).
    const flip = (value: string) => (value.startsWith("0") ? "1" : "0") + value.slice(1);
    expect((await t.fetch(good.replace(/sig=([0-9a-f]+)/, (_, sig: string) => `sig=${flip(sig)}`))).status).toBe(403);
    expect((await t.fetch(good.replace(/part=([0-9a-f-]+)/, (_, id: string) => `part=${flip(id)}`))).status).toBe(403);
    expect((await t.fetch("/data-export?part=nope&exp=1&sig=2")).status).toBe(400);
    vi.setSystemTime(new Date(Date.now() + 61 * 60 * 1000));
    expect((await t.fetch(good)).status).toBe(403);
  });

  test("a new download replaces the last one, and a build in progress is not started twice", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const first = await couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" });
    const again = await couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: false, p_language: "en" });
    expect(again.id).toBe(first.id);
    await run(t);
    const [firstLink] = await couple.first.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: first.id });
    expect((await t.fetch(pathOf(firstLink!.url))).status).toBe(200);

    const second = await couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" });
    expect(second.id).not.toBe(first.id);
    await run(t);
    expect((await t.fetch(pathOf(firstLink!.url))).status).toBe(404);
    expect(await t.run((ctx) => ctx.db.query("data_export_parts").collect())).toHaveLength(1);
  });

  test("is limited to three a day", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (let attempt = 0; attempt < 3; attempt += 1) await requestExport(t, couple.first);
    const refused = await failure(couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" }));
    expect(refused.code).toBe("53300");
    // The limit is per person.
    expect(await couple.second.as.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" })).toBeTruthy();
    vi.setSystemTime(new Date(Date.now() + 25 * 3600 * 1000));
    await requestExport(t, couple.first);
  });

  test("is refused while the account is being deleted", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.mutation(internal.accountDeletion.begin_account_deletion, { clerk_user_id: couple.first.subject });
    expect((await failure(couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" }))).code).toBe("42501");
  });
});

describe("how long a download lives", () => {
  test("the person can delete it early", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { status } = await requestExport(t, couple.first);
    expect(await couple.first.as.mutation(api.dataExport.delete_data_export, { p_export_id: status.id })).toBe(true);
    expect((await couple.first.as.query(api.dataExportStatus.get_data_export, {}))?.status).toBe("expired");
    expect(await t.run((ctx) => ctx.db.query("data_export_parts").collect())).toHaveLength(0);
    expect((await failure(couple.first.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: status.id }))).code).toBe("42501");
  });

  test("the hourly job deletes the files after three days and forgets the row after a month", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const { status } = await requestExport(t, couple.first);
    const storageIds = (await t.run((ctx) => ctx.db.query("data_export_parts").collect())).map((part) => part.storage_id!);

    vi.setSystemTime(new Date(Date.now() + 2 * 86_400_000));
    await t.mutation(internal.dataExport.expire_data_exports, {});
    expect((await couple.first.as.query(api.dataExportStatus.get_data_export, {}))?.status).toBe("ready");

    vi.setSystemTime(new Date(Date.now() + 2 * 86_400_000));
    await t.mutation(internal.dataExport.expire_data_exports, {});
    expect((await couple.first.as.query(api.dataExportStatus.get_data_export, {}))?.status).toBe("expired");
    for (const id of storageIds) expect(await t.run(async (ctx) => (await ctx.storage.get(id)) === null)).toBe(true);
    expect((await failure(couple.first.as.mutation(api.dataExport.create_data_export_download_links, { p_export_id: status.id }))).code).toBe("42501");

    vi.setSystemTime(new Date(Date.now() + 31 * 86_400_000));
    await t.mutation(internal.dataExport.expire_data_exports, {});
    expect(await couple.first.as.query(api.dataExportStatus.get_data_export, {})).toBeNull();
  });

  test("a build that never finishes is given up on, and its late action does nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const requested = await couple.first.as.mutation(api.dataExport.request_data_export, { p_include_files: true, p_language: "en" });
    vi.setSystemTime(new Date(Date.now() + 3 * 3_600_000));
    await t.mutation(internal.dataExport.expire_data_exports, {});
    expect(await couple.first.as.query(api.dataExportStatus.get_data_export, {})).toMatchObject({ id: requested.id, status: "failed", error_code: "export_timed_out" });
    await run(t);
    expect((await couple.first.as.query(api.dataExportStatus.get_data_export, {}))?.status).toBe("failed");
    expect(await t.run((ctx) => ctx.db.query("data_export_parts").collect())).toHaveLength(0);
  });

  test("a zip is not swept away as an orphan file", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await requestExport(t, couple.first);
    vi.setSystemTime(new Date(Date.now() + 26 * 3_600_000));
    await t.mutation(internal.media.sweep_orphan_storage, {});
    const [part] = await t.run((ctx) => ctx.db.query("data_export_parts").collect());
    expect(await t.run(async (ctx) => (await ctx.storage.get(part!.storage_id!)) !== null)).toBe(true);
  });

  test("deleting the account removes the downloads and their files", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await requestExport(t, couple.first);
    const [part] = await t.run((ctx) => ctx.db.query("data_export_parts").collect());
    await t.mutation(internal.accountDeletion.begin_account_deletion, { clerk_user_id: couple.first.subject });
    expect(await t.run((ctx) => ctx.db.query("data_exports").collect())).toHaveLength(0);
    expect(await t.run((ctx) => ctx.db.query("data_export_parts").collect())).toHaveLength(0);
    expect(await t.run(async (ctx) => (await ctx.storage.get(part!.storage_id!)) === null)).toBe(true);
  });
});
