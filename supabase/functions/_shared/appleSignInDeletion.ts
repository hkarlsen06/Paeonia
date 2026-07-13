/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_TOKEN_URL = `${APPLE_ISSUER}/auth/token`;
const APPLE_REVOKE_URL = `${APPLE_ISSUER}/auth/revoke`;
const APPLE_JWKS = jose.createRemoteJWKSet(
  new URL(`${APPLE_ISSUER}/auth/keys`),
);

export type AppleRevocationResult =
  | { status: "succeeded" }
  | { status: "manual_required"; errorCode: string };

interface AppleConfiguration {
  clientID: string;
  teamID: string;
  keyID: string;
  privateKey: string;
}

interface AppleTokenResponse {
  access_token?: unknown;
  refresh_token?: unknown;
  id_token?: unknown;
  error?: unknown;
}

class AppleDeletionError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "AppleDeletionError";
  }
}

export async function revokeAppleAuthorization(
  authorizationCode: string | null,
  expectedSubjects: ReadonlySet<string>,
): Promise<AppleRevocationResult> {
  if (!authorizationCode) {
    return {
      status: "manual_required",
      errorCode: "authorization_code_missing",
    };
  }

  if (expectedSubjects.size === 0) {
    return { status: "manual_required", errorCode: "apple_identity_missing" };
  }

  try {
    const configuration = appleConfiguration();
    const clientSecret = await makeAppleClientSecret(configuration);
    const tokenResponse = await exchangeAuthorizationCode(
      authorizationCode,
      configuration,
      clientSecret,
    );

    const idToken = requiredString(
      tokenResponse.id_token,
      "identity_token_missing",
    );
    const { payload } = await jose.jwtVerify(idToken, APPLE_JWKS, {
      issuer: APPLE_ISSUER,
      audience: configuration.clientID,
    });
    if (typeof payload.sub !== "string" || !expectedSubjects.has(payload.sub)) {
      throw new AppleDeletionError("apple_identity_mismatch");
    }

    const refreshToken = requiredString(
      tokenResponse.refresh_token,
      "refresh_token_missing",
    );
    await revokeToken(refreshToken, configuration, clientSecret);
    return { status: "succeeded" };
  } catch (error) {
    return {
      status: "manual_required",
      errorCode: stableAppleErrorCode(error),
    };
  }
}

export function appleIdentitySubjects(user: unknown): Set<string> {
  const subjects = new Set<string>();
  if (!user || typeof user !== "object") return subjects;

  const identities = (user as { identities?: unknown }).identities;
  if (!Array.isArray(identities)) return subjects;

  for (const value of identities) {
    if (!value || typeof value !== "object") continue;
    const identity = value as Record<string, unknown>;
    if (identity.provider !== "apple") continue;

    addString(subjects, identity.identity_id);

    const identityData = identity.identity_data;
    if (identityData && typeof identityData === "object") {
      addString(subjects, (identityData as Record<string, unknown>).sub);
    }
  }

  return subjects;
}

function appleConfiguration(): AppleConfiguration {
  const configuration = {
    clientID: Deno.env.get("APPLE_SIGN_IN_CLIENT_ID") ?? "no.paeonia.app",
    teamID: Deno.env.get("APPLE_SIGN_IN_TEAM_ID") ?? "",
    keyID: Deno.env.get("APPLE_SIGN_IN_KEY_ID") ?? "",
    privateKey: Deno.env.get("APPLE_SIGN_IN_PRIVATE_KEY") ?? "",
  };

  if (
    !configuration.clientID || !configuration.teamID ||
    !configuration.keyID || !configuration.privateKey
  ) {
    throw new AppleDeletionError("configuration_missing");
  }

  return configuration;
}

async function makeAppleClientSecret(
  configuration: AppleConfiguration,
): Promise<string> {
  try {
    const privateKey = await jose.importPKCS8(
      configuration.privateKey.replace(/\\n/g, "\n"),
      "ES256",
    );
    const now = Math.floor(Date.now() / 1000);

    return await new jose.SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: configuration.keyID })
      .setIssuer(configuration.teamID)
      .setSubject(configuration.clientID)
      .setAudience(APPLE_ISSUER)
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .sign(privateKey);
  } catch {
    throw new AppleDeletionError("client_secret_invalid");
  }
}

async function exchangeAuthorizationCode(
  authorizationCode: string,
  configuration: AppleConfiguration,
  clientSecret: string,
): Promise<AppleTokenResponse> {
  const response = await fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: configuration.clientID,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
    signal: AbortSignal.timeout(15_000),
  });

  const body = await safeJson(response) as AppleTokenResponse;
  if (!response.ok) {
    throw new AppleDeletionError(appleResponseError("token", body.error));
  }
  return body;
}

async function revokeToken(
  refreshToken: string,
  configuration: AppleConfiguration,
  clientSecret: string,
): Promise<void> {
  const response = await fetch(APPLE_REVOKE_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: configuration.clientID,
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
    signal: AbortSignal.timeout(15_000),
  });

  if (!response.ok) {
    const body = await safeJson(response) as AppleTokenResponse;
    throw new AppleDeletionError(appleResponseError("revoke", body.error));
  }
}

function requiredString(value: unknown, errorCode: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new AppleDeletionError(errorCode);
  }
  return value;
}

function appleResponseError(prefix: string, value: unknown): string {
  const suffix = typeof value === "string"
    ? value.toLowerCase().replace(/[^a-z0-9_]+/g, "_").slice(0, 80)
    : "unexpected_response";
  return `${prefix}_${suffix}`;
}

function stableAppleErrorCode(error: unknown): string {
  if (error instanceof AppleDeletionError) return error.code;
  if (error instanceof jose.errors.JOSEError) return "identity_token_invalid";
  if (error instanceof DOMException && error.name === "TimeoutError") {
    return "apple_timeout";
  }
  if (error instanceof TypeError) return "apple_unreachable";
  return "apple_unexpected_error";
}

async function safeJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return {};
  }
}

function addString(values: Set<string>, value: unknown) {
  if (typeof value === "string" && value.length > 0) values.add(value);
}
