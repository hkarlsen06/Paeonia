// Throwaway Apple-shaped certificate chains for tests. The extra dot in the file
// name keeps Convex from bundling it. Needs the openssl command line tool.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { sign } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";

// A chain is a root, an intermediate with the WWDR marker extension, and a leaf with the signing marker extension.
export const dir = mkdtempSync(join(tmpdir(), "paeonia-apple-chain-"));
const openssl = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: "pipe" });

export type Chain = { rootDer: Buffer; x5c: string[]; leafKey: string };

export function makeChain(name: string, options: { leafMarker?: boolean; intermediateMarker?: boolean } = {}): Chain {
  const { leafMarker = true, intermediateMarker = true } = options;
  const file = (suffix: string) => `${name}-${suffix}`;
  openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", file("root.key"));
  openssl("req", "-x509", "-new", "-key", file("root.key"), "-subj", `/CN=${name} Root`, "-days", "3650", "-out", file("root.pem"), "-addext", "basicConstraints=critical,CA:TRUE");
  writeFileSync(join(dir, file("int.ext")), `basicConstraints=critical,CA:TRUE\n${intermediateMarker ? "1.2.840.113635.100.6.2.1=DER:05:00\n" : ""}`);
  writeFileSync(join(dir, file("leaf.ext")), `basicConstraints=CA:FALSE\n${leafMarker ? "1.2.840.113635.100.6.11.1=DER:05:00\n" : ""}`);
  for (const [cert, signer, ext] of [["int", "root", "int.ext"], ["leaf", "int", "leaf.ext"]] as const) {
    openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", file(`${cert}.key`));
    openssl("req", "-new", "-key", file(`${cert}.key`), "-subj", `/CN=${name} ${cert}`, "-out", file(`${cert}.csr`));
    openssl("x509", "-req", "-in", file(`${cert}.csr`), "-CA", file(`${signer}.pem`), "-CAkey", file(`${signer}.key`), "-CAcreateserial", "-days", "3650", "-out", file(`${cert}.pem`), "-extfile", file(ext));
  }
  const der = (cert: string) => {
    openssl("x509", "-in", file(`${cert}.pem`), "-outform", "DER", "-out", file(`${cert}.der`));
    return readFileSync(join(dir, file(`${cert}.der`)));
  };
  return {
    rootDer: der("root"),
    x5c: [der("leaf"), der("int"), der("root")].map((buffer) => buffer.toString("base64")),
    leafKey: readFileSync(join(dir, file("leaf.key")), "utf8"),
  };
}

export function signJws(chain: Chain, payload: Record<string, unknown>): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const signingInput = `${encode({ alg: "ES256", x5c: chain.x5c })}.${encode(payload)}`;
  const signature = sign("sha256", Buffer.from(signingInput), { key: chain.leafKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${signature.toString("base64url")}`;
}

export function removeChains(): void {
  rmSync(dir, { recursive: true, force: true });
}
