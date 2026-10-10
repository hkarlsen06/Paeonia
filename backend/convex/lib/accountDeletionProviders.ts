// The outbound HTTP calls of account deletion (Clerk Backend API and Apple's
// Sign in with Apple REST API). Kept apart from the mutations so tests stub `fetch`
// in one place. Port of supabase/functions/_shared/appleSignInDeletion.ts.

const APPLE_ISSUER = "https://appleid.apple.com";
const CLERK_API = "https://api.clerk.com/v1";

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

/** The Apple subject ids linked to a Clerk user. Empty when the user has no Apple account. */
export async function fetchAppleSubjects(clerkUserId: string): Promise<Set<string>> {
  const subjects = new Set<string>();
  try {
    const response = await fetch(`${CLERK_API}/users/${encodeURIComponent(clerkUserId)}`, {
      headers: clerkHeaders(),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) return subjects;
    const body = (await response.json()) as {
      external_accounts?: { provider?: unknown; provider_user_id?: unknown }[];
    };
    for (const account of body.external_accounts ?? []) {
      if (typeof account.provider === "string" && account.provider.includes("apple")) {
        if (typeof account.provider_user_id === "string" && account.provider_user_id) {
          subjects.add(account.provider_user_id);
        }
      }
    }
  } catch {
    // No subjects means the caller falls back to manual revocation.
  }
  return subjects;
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
  expectedSubjects: ReadonlySet<string>,
): Promise<AppleRevocationResult> {
  if (!authorizationCode) return { status: "manual_required", errorCode: "authorization_code_missing" };
  if (expectedSubjects.size === 0) return { status: "manual_required", errorCode: "apple_identity_missing" };
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
    if (typeof claims.sub !== "string" || !expectedSubjects.has(claims.sub)) {
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
