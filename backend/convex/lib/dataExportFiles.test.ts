import { describe, expect, test } from "vitest";
import type { Id } from "../_generated/dataModel";
import { storeAndRecord } from "./dataExportFiles";

const storageId = "stored-1" as Id<"_storage">;
function fakeStorage() {
  const deleted: string[] = [];
  return {
    deleted,
    storage: {
      store: async () => storageId,
      delete: async (id: Id<"_storage">) => {
        deleted.push(id);
      },
    },
  };
}

describe("storing a file of a download", () => {
  test("a file whose record failed is deleted, because nothing else knows its id", async () => {
    const { storage, deleted } = fakeStorage();
    await expect(
      storeAndRecord(storage, new Blob(["zip"]), async () => {
        throw new Error("record failed");
      }),
    ).rejects.toThrow("record failed");
    expect(deleted).toEqual([storageId]);
  });

  test("a recorded file is kept", async () => {
    const { storage, deleted } = fakeStorage();
    expect(await storeAndRecord(storage, new Blob(["zip"]), async (id) => id)).toBe(storageId);
    expect(deleted).toEqual([]);
  });
});
