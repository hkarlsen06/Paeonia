import assert from "node:assert/strict";
import { test } from "node:test";
import { deliveryFor, isExpired, nextExpiryAlarm, type Attachment } from "./room.ts";

const now = Date.parse("2026-10-10T12:00:00.000Z");
const socket = (userId: string, closesAt: number, hasLeft?: boolean): Attachment => ({ userId, socketId: `${userId}-${closesAt}`, closesAt, hasLeft });

test("a socket expires only after its session ends", () => {
  assert.equal(isExpired(socket("a", now), now), false);
  assert.equal(isExpired(socket("a", now), now + 1), true);
});

test("a message reaches the other person's open sockets only", () => {
  assert.equal(deliveryFor(socket("b", now + 1), "a", now), "send");
  assert.equal(deliveryFor(socket("a", now + 1), "a", now), "skip");
  assert.equal(deliveryFor(socket("b", now + 1, true), "a", now), "skip");
});

test("a watcher past its session is closed instead of hearing the message", () => {
  assert.equal(deliveryFor(socket("b", now - 1), "a", now), "expire");
  // The sender's own expired socket is left to the sender's own check.
  assert.equal(deliveryFor(socket("a", now - 1), "a", now), "skip");
});

test("the alarm wakes just after the first open socket expires", () => {
  assert.equal(nextExpiryAlarm([]), null);
  assert.equal(nextExpiryAlarm([socket("a", now + 5_000, true)]), null);
  assert.equal(nextExpiryAlarm([socket("a", now + 5_000), socket("b", now + 2_000), socket("c", now + 1_000, true)]), now + 2_001);
});
