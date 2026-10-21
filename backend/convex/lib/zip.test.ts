import { describe, expect, test } from "vitest";
import { readZip, textOf } from "../dataExport.testHelpers";
import { crc32, ZipBuilder } from "./zip";

describe("ZipBuilder", () => {
  test("crc32 matches the standard check value", () => {
    expect(crc32(new TextEncoder().encode("123456789"))).toBe(0xcbf43926);
  });

  test("round trips stored, deflated and blob entries with UTF-8 names", async () => {
    const zip = new ZipBuilder(new Date("2026-10-21T08:30:00Z"));
    const long = "Paeonia ".repeat(500);
    await zip.addFile("a/readme.md", new TextEncoder().encode(long), { compress: true });
    await zip.addFile("b/tiny.txt", new TextEncoder().encode("hi"), { compress: true });
    await zip.addFile("blå/ø.txt", new TextEncoder().encode("norsk"), { compress: false });
    const photo = new Uint8Array([1, 2, 3, 4, 5]);
    zip.addStoredBlob("files/photo.jpg", new Blob([photo as BlobPart]), crc32(photo));
    expect(zip.fileCount).toBe(4);

    const archive = zip.toBlob();
    const files = await readZip(new Uint8Array(await archive.arrayBuffer()));
    expect([...files.keys()]).toEqual(["a/readme.md", "b/tiny.txt", "blå/ø.txt", "files/photo.jpg"]);
    expect(textOf(files, "a/readme.md")).toBe(long);
    expect(textOf(files, "blå/ø.txt")).toBe("norsk");
    expect([...files.get("files/photo.jpg")!]).toEqual([1, 2, 3, 4, 5]);
    // Long text is deflated, so the archive is smaller than its contents.
    expect(archive.size).toBeLessThan(long.length);
  });

  test("an empty archive is still a readable zip", async () => {
    const files = await readZip(new Uint8Array(await new ZipBuilder().toBlob().arrayBuffer()));
    expect(files.size).toBe(0);
  });
});
