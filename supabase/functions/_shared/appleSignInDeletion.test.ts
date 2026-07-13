import { assertEquals } from "jsr:@std/assert@1";
import { appleIdentitySubjects } from "./appleSignInDeletion.ts";

Deno.test("appleIdentitySubjects returns only stable Apple subject candidates", () => {
  const subjects = appleIdentitySubjects({
    identities: [
      {
        provider: "apple",
        id: "identity-row-id",
        identity_id: "apple-provider-subject",
        identity_data: { sub: "apple-token-subject" },
      },
      {
        provider: "google",
        identity_id: "google-subject",
        identity_data: { sub: "google-subject" },
      },
    ],
  });

  assertEquals(
    [...subjects].sort(),
    ["apple-provider-subject", "apple-token-subject"].sort(),
  );
});

Deno.test("appleIdentitySubjects fails closed when identities are unavailable", () => {
  assertEquals([...appleIdentitySubjects({})], []);
  assertEquals([...appleIdentitySubjects(null)], []);
});
