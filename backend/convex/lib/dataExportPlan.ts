// How the media files of an export are split into zip files. Pure, so a test can check the rules.

/** A zip file is built in memory, so it stays well under what an action can hold. */
export const PART_LIMIT_BYTES = 96 * 1024 * 1024;

/** `PART_LIMIT_BYTES`, or the deployment's `PAEONIA_EXPORT_PART_LIMIT_BYTES` when the server needs smaller zip files. */
export function exportPartLimitBytes(): number {
  const configured = Number(process.env.PAEONIA_EXPORT_PART_LIMIT_BYTES);
  return Number.isInteger(configured) && configured > 0 ? configured : PART_LIMIT_BYTES;
}
/** A zip central directory holds at most 65,535 files. Stay far below. */
export const PART_MAX_FILES = 3000;

export type PlannedFile = { id: string; size: number };

/**
 * Splits `files` into zip files in order. The first zip also holds the README and the data files, so it
 * starts with `firstPartUsedBytes` used. A file that is bigger than a whole zip gets a zip of its own.
 * Always returns at least one part.
 */
export function planParts(
  files: readonly PlannedFile[],
  firstPartUsedBytes: number,
  limit: number = PART_LIMIT_BYTES,
): string[][] {
  const parts: string[][] = [[]];
  let used = firstPartUsedBytes;
  for (const file of files) {
    const current = parts[parts.length - 1]!;
    const fits = used + file.size <= limit && current.length < PART_MAX_FILES;
    if (!fits && (current.length > 0 || parts.length === 1)) {
      parts.push([]);
      used = 0;
    }
    const target = parts[parts.length - 1]!;
    target.push(file.id);
    used += file.size;
  }
  return parts;
}

/** `Paeonia-my-data-2026-10-21.zip`, or `...-part-2-of-3.zip` when the download has several. */
export function partFileName(date: string, partNumber: number, partCount: number): string {
  return partCount === 1
    ? `Paeonia-my-data-${date}.zip`
    : `Paeonia-my-data-${date}-part-${partNumber}-of-${partCount}.zip`;
}

/** What part 1 keeps free for the README and the manifest when it plans which files go where. */
export const FIRST_PART_RESERVE_BYTES = 1024 * 1024;

/** A JSON data file holds at most about this much text, so no action holds a whole table. */
export const DATA_CHUNK_BYTES = 4 * 1024 * 1024;

/** A collect action stops starting new tables after this long and schedules the rest. A Node action may run 10 minutes. */
export const COLLECT_BUDGET_MS = 5 * 60 * 1000;

function configuredNumber(name: string, minimum: number): number | null {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return null;
  const value = Number(raw);
  return Number.isInteger(value) && value >= minimum ? value : null;
}

/** `DATA_CHUNK_BYTES`, or the deployment's `PAEONIA_EXPORT_CHUNK_BYTES`. */
export function exportChunkBytes(): number {
  return configuredNumber("PAEONIA_EXPORT_CHUNK_BYTES", 1) ?? DATA_CHUNK_BYTES;
}

/** `COLLECT_BUDGET_MS`, or the deployment's `PAEONIA_EXPORT_COLLECT_BUDGET_MS`. */
export function exportCollectBudgetMs(): number {
  return configuredNumber("PAEONIA_EXPORT_COLLECT_BUDGET_MS", 0) ?? COLLECT_BUDGET_MS;
}

/**
 * Cuts the rows of one table into JSON files of bounded size. Each file is the same text
 * `JSON.stringify(rows, null, 2)` writes for its rows. `add` returns a finished file once the rows
 * reach `limit` characters, and `finish` returns the rest.
 */
export class JsonChunker {
  private pieces: string[] = [];
  private length = 0;

  constructor(private readonly limit: number) {}

  add(row: unknown): { text: string; rows: number } | null {
    const piece = `  ${JSON.stringify(row, null, 2).replace(/\n/g, "\n  ")}`;
    this.pieces.push(piece);
    this.length += piece.length;
    return this.length >= this.limit ? this.finish() : null;
  }

  finish(): { text: string; rows: number } | null {
    if (this.pieces.length === 0) return null;
    const done = { text: `[\n${this.pieces.join(",\n")}\n]`, rows: this.pieces.length };
    this.pieces = [];
    this.length = 0;
    return done;
  }
}

/**
 * Where a table's data file sits in the archive: `chat/thread_messages.json`, or numbered files
 * (`chat/thread_messages-001.json`) when the table needed several.
 */
export function dataFilePath(folder: string, table: string, chunkIndex: number, chunkCount: number): string {
  return chunkCount === 1 ? `${folder}/${table}.json` : `${folder}/${table}-${String(chunkIndex + 1).padStart(3, "0")}.json`;
}
