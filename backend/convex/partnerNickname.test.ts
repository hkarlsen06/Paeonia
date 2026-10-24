import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { buildAppApsPayload } from "./lib/apns";
import { newUuid } from "./lib/ids";
import { enqueueNotificationForUser, enqueueWidgetUpdateAlert, notificationAlertTitle } from "./lib/notifications";
import { PARTNER_NICKNAME_MAX_LENGTH, nameForViewer } from "./lib/partnerNames";
import { addDevice, createCouple, createSignedInUser, newTest, relationshipStateOf, type TestUser } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

const setNickname = (user: TestUser, nickname: string | null) =>
  user.as.mutation(api.partnerNickname.set_partner_nickname, { p_nickname: nickname });
const lockScreenOf = (user: TestUser) => user.as.query(api.widget.get_lock_screen_state, { p_now: NOW });

describe("set_partner_nickname", () => {
  test("stores a trimmed nickname, and clearing it brings back the partner's own name", async () => {
    const t = newTest();
    const couple = await createCouple(t);

    expect(await setNickname(couple.first, "  Ellie   🌸 ")).toEqual({ partner_nickname: "Ellie 🌸" });
    expect(await relationshipStateOf(couple.first)).toMatchObject({
      partner_account_name: "Second Partner",
      partner_nickname: "Ellie 🌸",
    });

    expect(await setNickname(couple.first, "   ")).toEqual({ partner_nickname: null });
    expect(await relationshipStateOf(couple.first)).toMatchObject({ partner_nickname: null });
    expect(await setNickname(couple.first, "Babe")).toEqual({ partner_nickname: "Babe" });
    expect(await setNickname(couple.first, null)).toEqual({ partner_nickname: null });
    expect(await t.run((ctx) => nameForViewer(ctx, couple.first.userId, couple.second.userId))).toBe("Second Partner");
  });

  test("refuses a nickname that is too long or holds control characters", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await expect(setNickname(couple.first, "x".repeat(PARTNER_NICKNAME_MAX_LENGTH + 1))).rejects.toThrow(/23514/);
    await expect(setNickname(couple.first, "Ba\u0000be")).rejects.toThrow(/23514/);
    // Emoji count as one character each, and the limit is on characters, not bytes.
    await expect(setNickname(couple.first, "🌸".repeat(PARTNER_NICKNAME_MAX_LENGTH))).resolves.toBeTruthy();
  });

  test("is private: the partner sees no nickname and keeps their own", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await setNickname(couple.first, "Babe");
    expect(await relationshipStateOf(couple.second)).toMatchObject({
      partner_account_name: "First Partner",
      partner_nickname: null,
    });
    await setNickname(couple.second, "Honey");
    expect(await relationshipStateOf(couple.first)).toMatchObject({ partner_nickname: "Babe" });
    expect(await t.run((ctx) => nameForViewer(ctx, couple.second.userId, couple.first.userId))).toBe("Honey");
    // Nobody is called by a nickname they set for themselves, and a stranger sees the account name.
    expect(await t.run((ctx) => nameForViewer(ctx, couple.first.userId, couple.first.userId))).toBe("First Partner");
    const stranger = await createSignedInUser(t);
    expect(await t.run((ctx) => nameForViewer(ctx, stranger.userId, couple.second.userId))).toBe("Second Partner");
  });

  test("refuses someone without a couple, without an entitled couple, and signed out", async () => {
    const t = newTest();
    const alone = await createSignedInUser(t);
    await expect(setNickname(alone, "Babe")).rejects.toThrow(/42501/);
    await expect(t.mutation(api.partnerNickname.set_partner_nickname, { p_nickname: "Babe" })).rejects.toThrow();

    const lapsed = await createCouple(t, { entitled: false });
    await expect(setNickname(lapsed.first, "Babe")).rejects.toThrow(/42501/);
  });

  test("ends with the relationship, for both partners", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await setNickname(couple.first, "Babe");
    await setNickname(couple.second, "Honey");
    await t.mutation(internal.relationshipJobs.end_relationship_for_pair, {
      pair_id: couple.pairId,
      initiated_by_user_id: couple.first.userId,
      reason: "user_left",
    });
    const members = await t.run((ctx) => ctx.db.query("couple_members").collect());
    expect(members).toHaveLength(2);
    expect(members.every((member) => member.partner_nickname === undefined)).toBe(true);
    expect(await t.run((ctx) => nameForViewer(ctx, couple.first.userId, couple.second.userId))).toBe("Second Partner");
  });
});

describe("what the viewer is called", () => {
  test("push titles use the recipient's nickname for the sender", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await setNickname(couple.second, "Babe");
    const payload = { actor_user_id: couple.first.userId };
    const title = (viewer: TestUser, kind: string, locale = "en") =>
      t.run((ctx) => notificationAlertTitle(ctx, viewer.userId, kind, payload, locale));

    expect(await title(couple.second, "memory_created")).toBe("Babe added a memory");
    expect(await title(couple.second, "story_posted", "nb")).toBe("Babe delte en story");
    expect(await title(couple.second, "widget_updated")).toBe("Babe");

    // Each partner reads the other's push through their own nickname.
    await setNickname(couple.first, "Sweetie");
    const fromSecond = { actor_user_id: couple.second.userId };
    expect(await t.run((ctx) => notificationAlertTitle(ctx, couple.first.userId, "memory_created", fromSecond, "en"))).toBe(
      "Sweetie added a memory",
    );
  });

  test("a queued chat push and a widget alert carry the nickname", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    await setNickname(couple.second, "Babe");
    await t.run((ctx) =>
      enqueueNotificationForUser(ctx, {
        recipient_user_id: couple.second.userId,
        kind: "thread_message_sent",
        payload: { type: "thread_message_sent", actor_user_id: couple.first.userId },
      }),
    );
    await t.run((ctx) =>
      enqueueWidgetUpdateAlert(ctx, {
        couple_id: couple.coupleId,
        author_user_id: couple.first.userId,
        canvas_id: newUuid(),
        revision_id: newUuid(),
      }),
    );
    const rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(rows.map((row) => row.title).sort()).toEqual(["Babe", "Babe"]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a queued push picks up a nickname change or removal when it is sent", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    await setNickname(couple.second, "Babe");
    await t.run((ctx) =>
      enqueueNotificationForUser(ctx, {
        recipient_user_id: couple.second.userId,
        kind: "memory_created",
        payload: { type: "memory_created", actor_user_id: couple.first.userId },
      }),
    );
    await t.run((ctx) =>
      enqueueWidgetUpdateAlert(ctx, {
        couple_id: couple.coupleId,
        author_user_id: couple.first.userId,
        canvas_id: newUuid(),
        revision_id: newUuid(),
      }),
    );
    const rows = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    const sent = async () =>
      await Promise.all(
        rows.map(async (row) => {
          const prepared = await t.mutation(internal.pushQueue.prepare_notification, { outbox_id: row.id });
          const aps = buildAppApsPayload(prepared!);
          return { kind: row.kind, title: prepared!.title, sender_name: aps.sender_name };
        }),
      );
    const byKind = (list: Awaited<ReturnType<typeof sent>>) => list.sort((a, b) => a.kind.localeCompare(b.kind));

    expect(byKind(await sent())).toEqual([
      { kind: "memory_created", title: "Babe added a memory", sender_name: "Babe added a memory" },
      { kind: "widget_updated", title: "Babe", sender_name: "Babe" },
    ]);
    // The rows were queued with "Babe". The retry reads the nickname as it is now.
    await setNickname(couple.second, "Honey");
    expect(byKind(await sent()).map((row) => row.title)).toEqual(["Honey added a memory", "Honey"]);
    await setNickname(couple.second, null);
    expect(byKind(await sent())).toEqual([
      { kind: "memory_created", title: "First Partner added a memory", sender_name: "First Partner added a memory" },
      { kind: "widget_updated", title: "First Partner", sender_name: "First Partner" },
    ]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the Lock Screen widget state names the partner by the viewer's nickname", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await lockScreenOf(couple.first))!.partner).toMatchObject({ name: "Second Partner", uses_nickname: false });
    await setNickname(couple.first, "Babe");
    expect((await lockScreenOf(couple.first))!.partner).toMatchObject({ name: "Babe", uses_nickname: true });
    expect((await lockScreenOf(couple.second))!.partner).toMatchObject({ name: "First Partner", uses_nickname: false });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
