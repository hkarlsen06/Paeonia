import assert from "node:assert/strict";
import { test } from "node:test";
import { deliveryFor, isExpired, isTooLarge, MAX_MESSAGE_BYTES, MIN_REPLACE_AGE_MS, nextExpiryAlarm, socketToReplace, type Attachment } from "./room.ts";

const now = Date.parse("2026-10-10T12:00:00.000Z");
const socket = (userId: string, closesAt: number, hasLeft?: boolean, openedAt = now): Attachment => ({
  userId,
  socketId: `${userId}-${closesAt}`,
  openedAt,
  closesAt,
  hasLeft,
});

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

test("a message is measured in UTF-8 bytes", () => {
  assert.equal(isTooLarge("a".repeat(MAX_MESSAGE_BYTES)), false);
  assert.equal(isTooLarge("a".repeat(MAX_MESSAGE_BYTES + 1)), true);
  // Under the limit in UTF-16 units, over it in bytes: two bytes per unit.
  assert.equal(isTooLarge("é".repeat(MAX_MESSAGE_BYTES / 2 + 1)), true);
  assert.equal(isTooLarge("é".repeat(MAX_MESSAGE_BYTES / 2)), false);
  assert.equal(isTooLarge(new ArrayBuffer(MAX_MESSAGE_BYTES)), false);
  assert.equal(isTooLarge(new ArrayBuffer(MAX_MESSAGE_BYTES + 1)), true);
});

test("a full room replaces the connecting user's oldest open socket, and nobody else's", () => {
  const old = now - MIN_REPLACE_AGE_MS;
  const sockets = [
    socket("a", 1, false, old - 5_000),
    socket("a", 2, false, old),
    socket("b", 3, false, old - 9_000),
    socket("b", 4, false, old - 8_000),
  ];
  assert.equal(socketToReplace(sockets, "a", now), "a-1");
  assert.equal(socketToReplace(sockets, "b", now), "b-3");
  assert.equal(socketToReplace(sockets, "c", now), null);
  // A socket that left is already gone, so the next one is the oldest.
  assert.equal(socketToReplace([socket("a", 1, true, old - 5_000), ...sockets.slice(1)], "a", now), "a-2");
});

test("a socket younger than the replace age is kept, so two surfaces cannot evict each other in a loop", () => {
  const young = now - MIN_REPLACE_AGE_MS + 1;
  assert.equal(socketToReplace([socket("a", 1, false, young), socket("a", 2, false, young + 1)], "a", now), null);
});
