const drainSecret = Deno.env.get("DRAIN_SECRET") ?? "";

export const isDrainConfigured = drainSecret.length > 0;

// Digest comparison keeps timing independent of where two secrets diverge.
export async function drainRequestIsAuthorized(
  request: Request,
): Promise<boolean> {
  const provided = request.headers.get("x-drain-secret");
  if (!provided || !drainSecret) return false;

  const encoder = new TextEncoder();
  const [leftBuffer, rightBuffer] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(drainSecret)),
  ]);
  const left = new Uint8Array(leftBuffer);
  const right = new Uint8Array(rightBuffer);
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}
