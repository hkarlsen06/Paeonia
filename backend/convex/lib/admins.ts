import type { Doc } from "../_generated/dataModel";

// Admins are the Clerk users listed, comma separated, in the PAEONIA_ADMIN_CLERK_USER_IDS
// environment variable. It names Clerk users rather than Paeonia rows, so it survives a data
// wipe, and the app cannot change it.

export function adminClerkUserIds(): Set<string> {
  return new Set(
    (process.env.PAEONIA_ADMIN_CLERK_USER_IDS ?? "")
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean),
  );
}

export function isAdminUser(user: Doc<"users">): boolean {
  return adminClerkUserIds().has(user.clerk_user_id);
}
