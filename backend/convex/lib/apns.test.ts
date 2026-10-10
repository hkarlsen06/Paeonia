import { describe, expect, test } from "vitest";
import {
  apnsHeaders,
  apnsHost,
  buildAppApsPayload,
  buildAppRequest,
  buildProviderJwt,
  buildWidgetApsPayload,
  buildWidgetRequest,
  cachedProviderTokens,
  environmentOrder,
  readApnsConfig,
  sendWithEnvironmentFallback,
  type ApnsHttpResponse,
  type ApnsSendRequest,
  type ApnsTransport,
  type ClaimedNotification,
  type ClaimedWidgetPush,
} from "./apns";

const alert: ClaimedNotification = {
  outbox_id: "o1",
  target_device_id: "d1",
  push_token: "abc123",
  apns_environment: "sandbox",
  apns_push_type: "alert",
  apns_collapse_id: "daily:c1",
  title: "Alex",
  body: "Open Paeonia to see it.",
  payload: { type: "memory_created", route: "memories", deeplink: "paeonia://memories" },
};

describe("payload builders", () => {
  test("alert payload carries the stored copy and the redacted payload, nothing else", () => {
    expect(buildAppApsPayload(alert)).toEqual({
      aps: {
        alert: { body: "Open Paeonia to see it.", title: "Alex" },
        sound: "default",
        "mutable-content": 1,
        "content-available": 1,
      },
      type: "memory_created",
      route: "memories",
      deeplink: "paeonia://memories",
      sender_name: "Alex",
    });
  });

  test("an alert without a title leaves the title out and sends no sender name", () => {
    const payload = buildAppApsPayload({ ...alert, title: null, body: null });
    expect(payload.aps).toMatchObject({ alert: { body: "" } });
    expect((payload.aps as { alert: object }).alert).not.toHaveProperty("title");
    expect(JSON.parse(JSON.stringify(payload))).not.toHaveProperty("sender_name");
  });

  test("background payload wakes the app without any visible text", () => {
    const payload = buildAppApsPayload({ ...alert, apns_push_type: "background", title: null, body: null });
    expect(payload).toEqual({
      aps: { "content-available": 1 },
      type: "memory_created",
      route: "memories",
      deeplink: "paeonia://memories",
    });
  });

  test("widget payload is a content-changed push", () => {
    const widget: ClaimedWidgetPush = {
      outbox_id: "w1",
      target_widget_device_id: "wd",
      widget_push_token: "wtok",
      apns_environment: "production",
      apns_collapse_id: null,
      payload: { type: "widget_updated" },
    };
    expect(buildWidgetApsPayload(widget)).toEqual({ aps: { "content-changed": true }, type: "widget_updated" });
  });
});

describe("request builders", () => {
  test("app alert request", () => {
    const request = buildAppRequest(alert, "no.paeonia.app");
    expect(request).toMatchObject({
      token: "abc123",
      preferredEnvironment: "sandbox",
      topic: "no.paeonia.app",
      pushType: "alert",
      priority: "10",
      collapseId: "daily:c1",
    });
    expect(JSON.parse(request.body).aps.alert.title).toBe("Alex");
  });

  test("background requests use priority 5", () => {
    expect(buildAppRequest({ ...alert, apns_push_type: "background" }, "no.paeonia.app")).toMatchObject({
      pushType: "background",
      priority: "5",
    });
  });

  test("widget request uses the widgets topic and push type, priority 10, expiration 0", () => {
    const request = buildWidgetRequest(
      {
        outbox_id: "w1",
        target_widget_device_id: "wd",
        widget_push_token: "wtok",
        apns_environment: "production",
        apns_collapse_id: "widget:1",
        payload: {},
      },
      "no.paeonia.app",
    );
    expect(request).toMatchObject({
      token: "wtok",
      topic: "no.paeonia.app.push-type.widgets",
      pushType: "widgets",
      priority: "10",
      expiration: "0",
      collapseId: "widget:1",
      body: '{"aps":{"content-changed":true}}',
    });
  });

  test("headers include the optional fields only when set", () => {
    const base: ApnsSendRequest = {
      token: "tok",
      preferredEnvironment: "production",
      topic: "t",
      pushType: "alert",
      body: "{}",
    };
    expect(apnsHeaders("jwt", base)).toEqual({
      ":method": "POST",
      ":path": "/3/device/tok",
      authorization: "bearer jwt",
      "apns-topic": "t",
      "apns-push-type": "alert",
      "content-type": "application/json",
    });
    expect(apnsHeaders("jwt", { ...base, priority: "5", expiration: "0", collapseId: "c" })).toMatchObject({
      "apns-priority": "5",
      "apns-expiration": "0",
      "apns-collapse-id": "c",
    });
  });

  test("hosts and fallback order", () => {
    expect(apnsHost("production")).toBe("api.push.apple.com");
    expect(apnsHost("sandbox")).toBe("api.sandbox.push.apple.com");
    expect(environmentOrder("sandbox")).toEqual(["sandbox", "production"]);
    expect(environmentOrder("production")).toEqual(["production", "sandbox"]);
  });
});

describe("sendWithEnvironmentFallback", () => {
  const request = buildAppRequest(alert, "no.paeonia.app");

  function transport(responses: (ApnsHttpResponse | Error)[], tokenError?: (env: string) => boolean) {
    const log: string[] = [];
    const stub: ApnsTransport = {
      async providerToken(environment) {
        if (tokenError?.(environment)) throw new Error("bad key");
        return `jwt-${environment}`;
      },
      async post(environment, jwt) {
        log.push(`${environment}:${jwt}`);
        const next = responses.shift()!;
        if (next instanceof Error) throw next;
        return next;
      },
    };
    return { stub, log };
  }

  test("success on the preferred host", async () => {
    const { stub, log } = transport([{ status: 200, apnsId: "id-1" }]);
    expect(await sendWithEnvironmentFallback(request, stub)).toEqual({ ok: true, providerMessageId: "id-1", environment: "sandbox" });
    expect(log).toEqual(["sandbox:jwt-sandbox"]);
  });

  test("BadDeviceToken tries the other host and reports the one that worked", async () => {
    const { stub, log } = transport([{ status: 400, reason: "BadDeviceToken" }, { status: 200, apnsId: "id-2" }]);
    expect(await sendWithEnvironmentFallback(request, stub)).toMatchObject({ ok: true, environment: "production" });
    expect(log).toEqual(["sandbox:jwt-sandbox", "production:jwt-production"]);
  });

  test("BadDeviceToken on both hosts and 410 mark the token invalid", async () => {
    const both = transport([{ status: 400, reason: "BadDeviceToken" }, { status: 400, reason: "BadDeviceToken" }]);
    expect(await sendWithEnvironmentFallback(request, both.stub)).toEqual({
      ok: false,
      error: "BadDeviceToken",
      invalidToken: true,
      environment: "production",
    });
    const gone = transport([{ status: 410, reason: "Unregistered" }]);
    expect(await sendWithEnvironmentFallback(request, gone.stub)).toMatchObject({ ok: false, error: "Unregistered", invalidToken: true });
    expect(gone.log).toHaveLength(1);
  });

  test("other failures are not retried on the other host and are not invalid tokens", async () => {
    const { stub, log } = transport([{ status: 429, reason: "TooManyRequests" }]);
    const result = await sendWithEnvironmentFallback(request, stub);
    expect(result).toEqual({ ok: false, error: "TooManyRequests", environment: "sandbox" });
    expect(log).toHaveLength(1);
    const noReason = transport([{ status: 503 }]);
    expect(await sendWithEnvironmentFallback(request, noReason.stub)).toMatchObject({ error: "status 503" });
  });

  test("a provider token failure falls through to the next host", async () => {
    const { stub, log } = transport([{ status: 200, apnsId: "id-3" }], (env) => env === "sandbox");
    expect(await sendWithEnvironmentFallback(request, stub)).toMatchObject({ ok: true, environment: "production" });
    expect(log).toEqual(["production:jwt-production"]);
    const none = transport([], () => true);
    expect(await sendWithEnvironmentFallback(request, none.stub)).toEqual({ ok: false, error: "provider token: bad key" });
  });

  test("a network error propagates to the caller", async () => {
    const { stub } = transport([new Error("socket hang up")]);
    await expect(sendWithEnvironmentFallback(request, stub)).rejects.toThrow("socket hang up");
  });
});

describe("provider token", () => {
  async function pem() {
    const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    let binary = "";
    for (const byte of der) binary += String.fromCharCode(byte);
    const body = btoa(binary).replace(/(.{64})/g, "$1\n");
    return { pem: `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`, publicKey: pair.publicKey };
  }

  const decode = (part: string) => Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

  test("is an ES256 JWT that verifies with the public key", async () => {
    const { pem: privateKey, publicKey } = await pem();
    const jwt = await buildProviderJwt({ keyId: "KEY1234567", teamId: "TEAM123456", privateKey }, 1_790_000_000);
    const [header, claims, signature] = jwt.split(".");
    expect(JSON.parse(new TextDecoder().decode(decode(header)))).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(JSON.parse(new TextDecoder().decode(decode(claims)))).toEqual({ iss: "TEAM123456", iat: 1_790_000_000 });
    expect(decode(signature)).toHaveLength(64);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  test("accepts a key with escaped newlines, like an environment variable", async () => {
    const { pem: privateKey } = await pem();
    const jwt = await buildProviderJwt({ keyId: "K", teamId: "T", privateKey: privateKey.replace(/\n/g, "\\n") }, 1);
    expect(jwt.split(".")).toHaveLength(3);
  });

  test("is cached per environment until it is 40 minutes old", async () => {
    const { pem: privateKey } = await pem();
    let seconds = 1_000;
    const credentials = { keyId: "K", teamId: "T", privateKey };
    const tokens = cachedProviderTokens(() => credentials, () => seconds);
    const first = await tokens("sandbox");
    seconds += 2399;
    expect(await tokens("sandbox")).toBe(first);
    seconds += 1;
    expect(await tokens("sandbox")).not.toBe(first);
  });
});

describe("readApnsConfig", () => {
  test("lists missing settings and falls back to production credentials for sandbox", () => {
    expect(readApnsConfig({}).missing).toEqual(["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_PRIVATE_KEY"]);
    expect(readApnsConfig({}).bundleId).toBe("no.paeonia.app");
    const config = readApnsConfig({ APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_PRIVATE_KEY: "P", APNS_BUNDLE_ID: "x.y" });
    expect(config.missing).toEqual([]);
    expect(config.sandbox).toEqual({ keyId: "K", teamId: "T", privateKey: "P" });
    expect(config.bundleId).toBe("x.y");
    const split = readApnsConfig({
      APNS_KEY_ID: "K",
      APNS_TEAM_ID: "T",
      APNS_PRIVATE_KEY: "P",
      APNS_SANDBOX_KEY_ID: "SK",
      APNS_SANDBOX_PRIVATE_KEY: "SP",
    });
    expect(split.sandbox).toEqual({ keyId: "SK", teamId: "T", privateKey: "SP" });
    expect(split.production.keyId).toBe("K");
  });
});
