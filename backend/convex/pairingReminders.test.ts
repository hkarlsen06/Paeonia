import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createSignedInUser, grantLifetime, newTest, type TestConvex, type TestUser } from "./test.setup";

// 2026-10-10 is summer time in Oslo (UTC+2), so 12:00Z is 14:00 on the inviter's clock.
const NOW = "2026-10-10T12:00:00.000Z";
const at = (days: number, hours = 0) => new Date(Date.parse(NOW) + days * 86_400_000 + hours * 3_600_000).toISOString();

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
  process.env.INVITE_CODE_PEPPER = "test-pepper-value-for-pairing-invite-hashes";
});
afterEach(() => {
  vi.useRealTimers();
  delete process.env.INVITE_CODE_PEPPER;
});

let sequence = 0;
const operation = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: newUuid(),
  p_client_sequence: ++sequence,
  p_local_created_at: new Date().toISOString(),
});

async function waitingInviter(t: TestConvex): Promise<TestUser> {
  const user = await createSignedInUser(t, { name: "Inviter" });
  await grantLifetime(t, user.userId);
  await addDevice(t, user.userId, { timeZone: "Europe/Oslo", locale: "en-US" });
  return user;
}

async function createInvite(user: TestUser, code = "ABC123"): Promise<string> {
  return await user.as.mutation(api.pairing.create_pairing_invite, {
    p_invite_code: code,
    ...operation(),
    p_expires_at: at(30),
  });
}

/** Runs the reminder cron at `now` and returns how many pushes it queued. */
async function runCron(t: TestConvex, now: string): Promise<number> {
  vi.setSystemTime(new Date(now));
  return await t.mutation(internal.pairingReminders.send_pairing_invite_reminders, {});
}

async function deliveredReminders(t: TestConvex) {
  return (await deliverDuePushes(t)).filter((push) => push.payload.type === "pairing_invite_reminder");
}

describe("send_pairing_invite_reminders", () => {
  test("sends one reminder two days after the invite, and never a second", async () => {
    const t = newTest();
    const inviter = await waitingInviter(t);
    const inviteId = await createInvite(inviter);

    expect(await runCron(t, at(1, 23))).toBe(0);
    expect(await runCron(t, at(2, 1))).toBe(1);
    const [reminder, ...others] = await deliveredReminders(t);
    expect(others).toEqual([]);
    expect(reminder.payload).toEqual({
      type: "pairing_invite_reminder",
      invite_id: inviteId,
      route: "home",
      deeplink: "paeonia://home",
    });
    expect(reminder.title).toBeTruthy();
    expect(reminder.body).toBeTruthy();

    expect(await runCron(t, at(3, 1))).toBe(0);
    expect(await runCron(t, at(10, 1))).toBe(0);
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.filter((row) => row.kind === "pairing_invite_reminder")).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("sends nothing once the partner joined, even when the push was already queued", async () => {
    const t = newTest();
    const inviter = await waitingInviter(t);
    await createInvite(inviter, "ABC123");
    const partner = await createSignedInUser(t, { name: "Partner" });
    vi.setSystemTime(new Date(at(1)));
    await partner.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() });
    expect(await runCron(t, at(2, 1))).toBe(0);
    expect(await deliveredReminders(t)).toEqual([]);

    // Queued first, then the partner joins before the send.
    const second = newTest();
    const secondInviter = await waitingInviter(second);
    vi.setSystemTime(new Date(NOW));
    await createInvite(secondInviter, "K7M2PQ");
    expect(await runCron(second, at(2, 1))).toBe(1);
    const secondPartner = await createSignedInUser(second, { name: "Partner" });
    await secondPartner.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "K7M2PQ", ...operation() });
    expect(await deliveredReminders(second)).toEqual([]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    await second.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("skips a cancelled invite and reminds only about the newest of two waiting ones", async () => {
    const t = newTest();
    const cancelled = await waitingInviter(t);
    const cancelledId = await createInvite(cancelled, "ABC123");
    await cancelled.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: cancelledId });

    const twice = await waitingInviter(t);
    await createInvite(twice, "K7M2PQ");
    vi.setSystemTime(new Date(at(0, 1)));
    const newerId = await createInvite(twice, "N9N9N9");

    expect(await runCron(t, at(2, 2))).toBe(1);
    const reminders = await deliveredReminders(t);
    expect(reminders.map((push) => push.payload.invite_id)).toEqual([newerId]);
    expect(await runCron(t, at(3, 2))).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("waits out the inviter's night", async () => {
    const t = newTest();
    const inviter = await waitingInviter(t);
    await createInvite(inviter);

    // 21:30Z is 23:30 in Oslo, and 04:30Z is 06:30.
    expect(await runCron(t, at(2, 9.5))).toBe(0);
    expect(await runCron(t, at(2, 16.5))).toBe(0);
    // 05:30Z is 07:30 in Oslo.
    expect(await runCron(t, at(2, 17.5))).toBe(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
