import { describe, expect, test } from "vitest";
import { createSignedInUser, newTest } from "../test.setup";
import { runClientOperation } from "./clientOperations";
import { newUuid } from "./ids";

function input(overrides: Partial<Parameters<typeof runClientOperation>[2]> = {}) {
  return {
    client_operation_id: newUuid(),
    client_id: newUuid(),
    client_sequence: 1,
    local_created_at: "2026-10-10T12:00:00.000Z",
    operation_kind: "create_memory",
    idempotency_scope: "memory",
    request: { title: "Trip" },
    ...overrides,
  };
}

describe("runClientOperation", () => {
  test("runs the work once and replays the stored response", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const op = input();
    let runs = 0;
    const work = async () => {
      runs += 1;
      return { memory_id: "abc" };
    };
    const first = await user.as.run((ctx) => runClientOperation(ctx, user.userId, op, work));
    const second = await user.as.run((ctx) => runClientOperation(ctx, user.userId, op, work));
    expect(first).toEqual({ memory_id: "abc" });
    expect(second).toEqual({ memory_id: "abc" });
    expect(runs).toBe(1);
    const row = await t.run((ctx) => ctx.db.query("client_operations").first());
    expect(row).toMatchObject({ status: "succeeded", user_id: user.userId, stored_response: { memory_id: "abc" } });
    expect(row?.request_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(row?.response_hash).toMatch(/^[0-9a-f]{64}$/);
  });

  test("key order in the request does not change the hash", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const op = input({ request: { a: 1, b: { c: 2, d: 3 } } });
    await user.as.run((ctx) => runClientOperation(ctx, user.userId, op, async () => null));
    const replay = { ...op, request: { b: { d: 3, c: 2 }, a: 1 } };
    await expect(
      user.as.run((ctx) => runClientOperation(ctx, user.userId, replay, async () => "unused")),
    ).resolves.toBeNull();
  });

  test("a different request under the same operation id fails with 23505", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const op = input();
    await user.as.run((ctx) => runClientOperation(ctx, user.userId, op, async () => 1));
    await expect(
      user.as.run((ctx) =>
        runClientOperation(ctx, user.userId, { ...op, request: { title: "Other" } }, async () => 2),
      ),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
  });

  test("operation ids are scoped per user", async () => {
    const t = newTest();
    const a = await createSignedInUser(t);
    const b = await createSignedInUser(t);
    const op = input();
    await a.as.run((ctx) => runClientOperation(ctx, a.userId, op, async () => "a"));
    await expect(b.as.run((ctx) => runClientOperation(ctx, b.userId, op, async () => "b"))).resolves.toBe("b");
  });

  test("a failing operation leaves no row, so the client can retry", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const op = input();
    await expect(
      user.as.run((ctx) =>
        runClientOperation(ctx, user.userId, op, async () => {
          throw new Error("boom");
        }),
      ),
    ).rejects.toThrow(/boom/);
    expect(await t.run(async (ctx) => (await ctx.db.query("client_operations").collect()).length)).toBe(0);
    await expect(user.as.run((ctx) => runClientOperation(ctx, user.userId, op, async () => "ok"))).resolves.toBe("ok");
  });

  test("void work stores null", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const op = input();
    await user.as.run((ctx) => runClientOperation(ctx, user.userId, op, async () => undefined));
    await expect(
      user.as.run((ctx) => runClientOperation(ctx, user.userId, op, async () => "unused")),
    ).resolves.toBeNull();
  });

  test("rejects a user with a pending account deletion", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    await t.run(async (ctx) => {
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: user.userId,
        auth_provider: "unknown",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        created_at: "2026-10-10T12:00:00.000Z",
        updated_at: "2026-10-10T12:00:00.000Z",
      });
    });
    await expect(
      user.as.run((ctx) => runClientOperation(ctx, user.userId, input(), async () => 1)),
    ).rejects.toThrow(/42501.*account deletion is in progress/);
  });

  test("applies the client_operations check constraints", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    await expect(
      user.as.run((ctx) => runClientOperation(ctx, user.userId, input({ client_sequence: 0 }), async () => 1)),
    ).rejects.toThrow(/client_operations_client_sequence_check/);
  });
});
