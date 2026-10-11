import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";
import { verifyTicket } from "./ticket.ts";

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
