const encoder = new TextEncoder();

/** JSON with object keys sorted at every level. Equal values give equal strings. */
export function stableStringify(value: unknown): string {
  return JSON.stringify(sortKeys(value)) ?? "null";
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortKeys);
  }
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(record).sort()) {
      if (record[key] !== undefined) {
        sorted[key] = sortKeys(record[key]);
      }
    }
    return sorted;
  }
  return value;
}

/** The text Postgres prints for a jsonb value (`{"a": 1, "b": [2, 3]}`). */
export function jsonbText(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(jsonbText).join(", ")}]`;
  }
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, item]) => item !== undefined)
      .map(([key, item]) => `${JSON.stringify(key)}: ${jsonbText(item)}`);
    return `{${entries.join(", ")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

/** Equivalent of `octet_length(value::text)` for a jsonb column. */
export function jsonbByteLength(value: unknown): number {
  return encoder.encode(jsonbText(value)).length;
}

export function isJsonObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
