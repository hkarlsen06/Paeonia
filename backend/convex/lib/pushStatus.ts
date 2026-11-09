/** Where a push outbox row stands. The queue sets `sent_at` or `failed_at` once, never both. */
export type PushStatus = "pending" | "sent" | "failed";

export function pushStatus(row: { sent_at?: string; failed_at?: string }): PushStatus {
  if (row.failed_at !== undefined) return "failed";
  if (row.sent_at !== undefined) return "sent";
  return "pending";
}
