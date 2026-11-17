import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "edge-runtime",
    // The edge-runtime environment copies Node's globals into its VM. Reading
    // Node 26's localStorage without --localstorage-file prints a warning in
    // every worker, and Convex functions have no localStorage anyway.
    execArgv: ["--no-experimental-webstorage"],
    server: { deps: { inline: ["convex-test"] } },
  },
});
