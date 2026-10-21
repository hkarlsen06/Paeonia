// The outbound HTTP calls of account deletion (Clerk Backend API, Apple's
// Sign in with Apple REST API, and PostHog's person API). Kept apart from the mutations so tests stub `fetch`
// in one place. Port of supabase/functions/_shared/appleSignInDeletion.ts.

const APPLE_ISSUER = "https://appleid.apple.com";
const CLERK_API = "https://api.clerk.com/v1";
// The app's usage statistics project on PostHog EU Cloud.
const POSTHOG_PROJECT_API = "https://eu.posthog.com/api/projects/309819";

export type AppleRevocationResult =
  | { status: "succeeded" }
  | { status: "manual_required"; errorCode: string };

/** An error whose `code` is safe to store and show to operators. */
export class ProviderError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "ProviderError";
  }
}

function sanitizeCode(value: string, max: number): string {
  return value.toLowerCase().replace(/[^a-z0-9_]+/g, "_").slice(0, max);
}

/** Stable, secret-free code for a failed Clerk call. */
export function stableAuthDeleteErrorCode(error: unknown): string {
  if (error instanceof ProviderError) return error.code;
  return "auth_delete_unexpected";
}

function clerkHeaders(): Record<string, string> {
  const key = process.env.CLERK_SECRET_KEY;
  if (!key) throw new ProviderError("auth_configuration_missing");
  return { Authorization: `Bearer ${key}` };
}

type ClerkExternalAccount = { provider?: unknown; provider_user_id?: unknown; verification?: { status?: unknown } | null };

/** The external accounts Clerk lists for a user, or null when Clerk could not be asked. */
async function fetchExternalAccounts(clerkUserId: string): Promise<ClerkExternalAccount[] | null> {
  try {
    const response = await fetch(`${CLERK_API}/users/${encodeURIComponent(clerkUserId)}`, {
      headers: clerkHeaders(),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) return null;
    const body = (await response.json()) as { external_accounts?: ClerkExternalAccount[] };
    return body.external_accounts ?? [];
  } catch {
    return null;
  }
}

/**
 * The Apple subject ids linked to a Clerk user. Empty when the user has no Apple account, and null
 * when Clerk could not be asked. Null is not "no Apple": the caller must not decide on it.
 */
export async function fetchAppleSubjects(clerkUserId: string): Promise<Set<string> | null> {
  const accounts = await fetchExternalAccounts(clerkUserId);
  if (accounts === null) return null;
  const subjects = new Set<string>();
  for (const account of accounts) {
    if (typeof account.provider === "string" && account.provider.includes("apple")) {
      if (typeof account.provider_user_id === "string" && account.provider_user_id) {
        subjects.add(account.provider_user_id);
      }
    }
  }
  return subjects;
}

/**
 * The sign-in methods a Clerk user has linked and verified, or null when Clerk
 * could not be asked. A person can link both Apple and Google to one account.
 */
export async function fetchLinkedSignInProviders(clerkUserId: string): Promise<Set<"apple" | "google"> | null> {
  const accounts = await fetchExternalAccounts(clerkUserId);
  if (accounts === null) return null;
  const providers = new Set<"apple" | "google">();
  for (const account of accounts) {
    if (typeof account.provider !== "string" || account.verification?.status !== "verified") continue;
    if (account.provider.includes("apple")) providers.add("apple");
    if (account.provider.includes("google")) providers.add("google");
  }
  return providers;
}

/** Deletes the Clerk user, which also ends every session. A missing user counts as deleted. */
export async function deleteClerkUser(clerkUserId: string): Promise<void> {
  let response: Response;
  try {
    response = await fetch(`${CLERK_API}/users/${encodeURIComponent(clerkUserId)}`, {
      method: "DELETE",
      headers: clerkHeaders(),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    if (error instanceof ProviderError) throw error;
    throw new ProviderError("auth_unreachable");
  }
  if (!response.ok && response.status !== 404) {
    throw new ProviderError(`auth_http_${response.status}`);
  }
}

// ---- Sign in with Apple ----

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function textBase64Url(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function makeAppleClientSecret(config: AppleConfig): Promise<string> {
  try {
    const pem = config.privateKey
      .replace(/\\n/g, "\n")
      .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
      .replace(/\s+/g, "");
    const der = Uint8Array.from(atob(pem), (char) => char.charCodeAt(0));
    const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    const now = Math.floor(Date.now() / 1000);
    const signingInput = `${textBase64Url({ alg: "ES256", kid: config.keyId })}.${textBase64Url({
      iss: config.teamId,
      sub: config.clientId,
      aud: APPLE_ISSUER,
      iat: now,
      exp: now + 300,
    })}`;
    // WebCrypto returns the raw r||s signature that JWS ES256 uses.
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    );
    return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
  } catch {
    throw new ProviderError("client_secret_invalid");
  }
}

type AppleConfig = { clientId: string; teamId: string; keyId: string; privateKey: string };

function appleConfig(): AppleConfig {
  const config = {
    clientId: process.env.APPLE_SIGN_IN_CLIENT_ID || "no.paeonia.app",
    teamId: process.env.APPLE_SIGN_IN_TEAM_ID ?? "",
    keyId: process.env.APPLE_SIGN_IN_KEY_ID ?? "",
    privateKey: process.env.APPLE_SIGN_IN_PRIVATE_KEY ?? "",
  };
  if (!config.clientId || !config.teamId || !config.keyId || !config.privateKey) {
    throw new ProviderError("configuration_missing");
  }
  return config;
}

async function appleRequest(path: string, params: Record<string, string>): Promise<Record<string, unknown>> {
  const response = await fetch(`${APPLE_ISSUER}${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
    signal: AbortSignal.timeout(15_000),
  });
  let body: Record<string, unknown> = {};
  try {
    body = (await response.json()) as Record<string, unknown>;
  } catch {
    // Revoke answers with an empty body on success.
  }
  if (!response.ok) {
    const suffix = typeof body.error === "string" ? sanitizeCode(body.error, 80) : "unexpected_response";
    throw new ProviderError(`${path === "/auth/token" ? "token" : "revoke"}_${suffix}`);
  }
  return body;
}

function requiredString(value: unknown, errorCode: string): string {
  if (typeof value !== "string" || value.length === 0) throw new ProviderError(errorCode);
  return value;
}

/** The claims of an id token Apple returned straight from its token endpoint over TLS. */
function idTokenClaims(idToken: string): Record<string, unknown> {
  try {
    const payload = idToken.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(payload), (char) => char.charCodeAt(0))));
  } catch {
    throw new ProviderError("identity_token_invalid");
  }
}

/**
 * Exchanges the authorization code, checks that the Apple identity belongs to
 * the account being deleted, and revokes the refresh token. Never throws.
 * ponytail: the id token signature is not verified because it comes directly
 * from Apple's token endpoint over TLS. Add JWKS verification if the token ever
 * arrives from the client.
 */
export async function revokeAppleAuthorization(
  authorizationCode: string | null,
  expectedSubjects: ReadonlySet<string> | null,
): Promise<AppleRevocationResult> {
  if (!authorizationCode) return { status: "manual_required", errorCode: "authorization_code_missing" };
  if (expectedSubjects?.size === 0) return { status: "manual_required", errorCode: "apple_identity_missing" };
  try {
    const config = appleConfig();
    const clientSecret = await makeAppleClientSecret(config);
    const tokens = await appleRequest("/auth/token", {
      client_id: config.clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    });
    const claims = idTokenClaims(requiredString(tokens.id_token, "identity_token_missing"));
    const expired = typeof claims.exp === "number" && claims.exp * 1000 < Date.now();
    if (claims.iss !== APPLE_ISSUER || claims.aud !== config.clientId || expired) {
      throw new ProviderError("identity_token_invalid");
    }
    // Null means Clerk could not name the linked Apple accounts. The code is still valid proof of one
    // Apple sign-in by the person who is deleting, and it can only revoke that sign-in.
    if (typeof claims.sub !== "string" || (expectedSubjects !== null && !expectedSubjects.has(claims.sub))) {
      throw new ProviderError("apple_identity_mismatch");
    }
    await appleRequest("/auth/revoke", {
      client_id: config.clientId,
      client_secret: clientSecret,
      token: requiredString(tokens.refresh_token, "refresh_token_missing"),
      token_type_hint: "refresh_token",
    });
    return { status: "succeeded" };
  } catch (error) {
    let errorCode = "apple_unexpected_error";
    if (error instanceof ProviderError) errorCode = error.code;
    else if (error instanceof DOMException && error.name === "TimeoutError") errorCode = "apple_timeout";
    else if (error instanceof TypeError) errorCode = "apple_unreachable";
    return { status: "manual_required", errorCode };
  }
}

// ---- PostHog ----

function posthogKey(): string {
  const key = process.env.POSTHOG_PERSONAL_API_KEY;
  if (!key) throw new ProviderError("analytics_configuration_missing");
  return key;
}

/** Sends one request to the PostHog project API and returns the parsed body. */
async function posthogRequest(path: string, body: unknown): Promise<unknown> {
  const key = posthogKey();
  let response: Response;
  try {
    response = await fetch(`${POSTHOG_PROJECT_API}${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new ProviderError("analytics_unreachable");
  }
  if (!response.ok) {
    throw new ProviderError(`analytics_http_${response.status}`);
  }
  try {
    return await response.json();
  } catch {
    throw new ProviderError("analytics_unreadable_response");
  }
}

/**
 * Asks PostHog to delete people with their events and recordings, by the ids
 * the app identified them with (`distinct_ids`) or by PostHog's own ids
 * (`ids`). PostHog accepts the request and deletes in a weekly batch. It never
 * queues the same person's deletion twice, so a retry is safe.
 */
async function deleteAnalyticsPersons(target: { distinct_ids: string[] } | { ids: string[] }): Promise<void> {
  const body = (await posthogRequest("/persons/bulk_delete/", {
    ...target,
    delete_events: true,
    delete_recordings: true,
  })) as { deletion_errors?: unknown } | null;
  // A 202 can still report a person whose deletion failed.
  if (Array.isArray(body?.deletion_errors) && body.deletion_errors.length > 0) {
    throw new ProviderError("analytics_deletion_failed");
  }
}

/** Deletes the PostHog person the app identified with this Paeonia user id. */
export function deleteAnalyticsPerson(userId: string): Promise<void> {
  return deleteAnalyticsPersons({ distinct_ids: [userId] });
}

/** How many people one run deletes. PostHog's bulk delete takes at most 1000. */
const INACTIVE_BATCH = 1000;

/**
 * Deletes everyone PostHog has not heard from in a year, so usage statistics
 * are kept for a year after someone's last use. PostHog cannot delete events
 * by age, only whole people. Returns how many it asked PostHog to delete.
 * ponytail: one batch per run. A month with more than 1000 such people leaves
 * the rest for the next run.
 */
export async function deleteInactiveAnalyticsPersons(): Promise<number> {
  const body = (await posthogRequest("/query/", {
    query: {
      kind: "HogQLQuery",
      query: `SELECT person_id FROM events GROUP BY person_id HAVING max(timestamp) < now() - INTERVAL 12 MONTH LIMIT ${INACTIVE_BATCH}`,
    },
  })) as { results?: unknown } | null;
  if (!Array.isArray(body?.results)) {
    throw new ProviderError("analytics_unreadable_response");
  }
  const ids = body.results.map((row) => String((row as unknown[])[0]));
  if (ids.length > 0) {
    await deleteAnalyticsPersons({ ids });
  }
  return ids.length;
}
