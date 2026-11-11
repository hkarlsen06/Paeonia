import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { op } from "./media.testing";
import { addDevice, createCouple, newTest } from "./test.setup";

vi.mock("./lib/notifications", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./lib/notifications")>()),
  enqueueLetterNotification: async () => {
    throw new Error("the push queue is down");
  },
}));

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-11-10T20:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

test("a letter is delivered even when queueing its push throws", async () => {
  const t = newTest();
  const couple = await createCouple(t);
  await addDevice(t, couple.second.userId);
  const sendAt = (letterId: string) =>
    couple.first.as.mutation(api.letters.send_letter, {
      p_letter_id: letterId,
      p_template_key: "blank",
      p_body: "See you soon",
      p_delivery_kind: "at",
      p_deliver_at: "2026-11-10T21:00:00.000Z",
      ...op(),
    });
  const scheduled = crypto.randomUUID();
  const swept = crypto.randomUUID();
  await sendAt(scheduled);
  await sendAt(swept);

  vi.setSystemTime(new Date("2026-11-10T21:00:00.000Z"));
  await t.mutation(internal.letters.deliver_letter, { letter_id: scheduled });
  await t.mutation(internal.letters.deliver_due_letters, {});
  await vi.runOnlyPendingTimersAsync();
  await t.finishInProgressScheduledFunctions().catch(() => {});

  const waiting = (await couple.second.as.query(api.letters.get_letters, {})).waiting.map((letter) => letter.id);
  expect(waiting.sort()).toEqual([scheduled, swept].sort());
});
