import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";
import { roomName, verifyTicket } from "./ticket.ts";

const secret = "test-relay-secret";
const now = Date.parse("2026-10-10T12:00:00.000Z");

function sign(claims: object, key = secret): string {
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  return `${payload}.${createHmac("sha256", key).update(payload).digest("hex")}`;
}

test("accepts a valid ticket", async () => {
  const ticket = sign({ c: "couple-1", u: "user-1", e: now + 60_000 });
  assert.deepEqual(await verifyTicket(ticket, secret, now), { coupleId: "couple-1", userId: "user-1", expiresAt: now + 60_000 });
});

test("rejects expired, forged, and malformed tickets", async () => {
  assert.equal(await verifyTicket(sign({ c: "couple-1", u: "user-1", e: now }), secret, now), null);
  assert.equal(await verifyTicket(sign({ c: "couple-1", u: "user-1", e: now + 60_000 }, "other"), secret, now), null);
  const valid = sign({ c: "couple-1", u: "user-1", e: now + 60_000 });
  const forged = `${Buffer.from(JSON.stringify({ c: "couple-2", u: "user-1", e: now + 60_000 })).toString("base64url")}.${valid.split(".")[1]}`;
  assert.equal(await verifyTicket(forged, secret, now), null);
  assert.equal(await verifyTicket(sign({ c: "couple-1", e: now + 60_000 }), secret, now), null);
  assert.equal(await verifyTicket("", secret, now), null);
  assert.equal(await verifyTicket(`${valid}.x`, secret, now), null);
});

test("a ticket without a channel joins the couple's canvas room", async () => {
  const ticket = await verifyTicket(sign({ c: "couple-1", u: "user-1", e: now + 60_000 }), secret, now);
  assert.equal(ticket?.channel, undefined);
  assert.equal(roomName(ticket!), "couple-1");
});

test("a ticket with an allowed channel joins that channel's room", async () => {
  const ticket = await verifyTicket(sign({ c: "couple-1", u: "user-1", e: now + 60_000, ch: "draw_and_guess" }), secret, now);
  assert.deepEqual(ticket, { coupleId: "couple-1", userId: "user-1", expiresAt: now + 60_000, channel: "draw_and_guess" });
  assert.equal(roomName(ticket!), "couple-1:draw_and_guess");
});

test("every game kind is an allowed channel", async () => {
  for (const ch of ["mind_meld", "exquisite_corpse", "story_chain", "connect_four", "dots_and_boxes", "ultimate_tic_tac_toe"]) {
    const ticket = await verifyTicket(sign({ c: "couple-1", u: "user-1", e: now + 60_000, ch }), secret, now);
    assert.deepEqual(ticket, { coupleId: "couple-1", userId: "user-1", expiresAt: now + 60_000, channel: ch });
    assert.equal(roomName(ticket!), `couple-1:${ch}`);
  }
});

test("rejects a channel that is not on the allowlist, or is not a string", async () => {
  for (const ch of ["canvas", "chess", "", "mind_meld:x", "Mind_Meld", "draw_and_guess:x", "../couple-2", 7, null, ["draw_and_guess"]]) {
    assert.equal(await verifyTicket(sign({ c: "couple-1", u: "user-1", e: now + 60_000, ch }), secret, now), null, JSON.stringify(ch));
  }
});

test("a signed channel cannot be removed or swapped", async () => {
  const valid = sign({ c: "couple-1", u: "user-1", e: now + 60_000, ch: "draw_and_guess" });
  const stripped = `${Buffer.from(JSON.stringify({ c: "couple-1", u: "user-1", e: now + 60_000 })).toString("base64url")}.${valid.split(".")[1]}`;
  assert.equal(await verifyTicket(stripped, secret, now), null);
});
