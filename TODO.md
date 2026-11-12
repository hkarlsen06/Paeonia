# Follow-up work

## Convex runtime and capacity, November 7, 2026

The hosted backend and dashboard now use `precompiled-2026-11-12-cc07c9e`
with packaged jemalloc (upgraded from `a7376b7` on November 12, 2026). Authentication, live writes and subscriptions, signed
media, file backups, rollback rehearsals and restarts passed. Upstream marks this
build as a prerelease. Hosted configuration is documented in
[backend/AGENTS.md](backend/AGENTS.md). Shared runtime tools and backup-retention
follow-up live in the Tidex checkout under `backend/ops/convex-runtime/` and
`TODO.md`.

- [ ] Observe Paeonia on `one-s` for at least 48 hours, including normal use,
  backend deploys and backup/export cycles. Record working memory excluding
  inactive file cache, process RSS, container and host swap, memory-limit/OOM
  events, CPU and request errors. Check whether memory settles after bursts.
  The immediate post-restart snapshot does not establish long-term retention
  or production capacity.
- [ ] Verify APNs delivery through the Node action runtime on developer-owned
  test devices after the upgrade. Check foreground, background and terminated-app
  delivery, badges and notification privacy settings. The Node action and
  subscription checks did not verify an actual phone receiving a push.
- [ ] Profile and reduce the broad reads in `badges:get_badges` and repeated
  badge preparation across push targets. Start with `backend/convex/lib/badges.ts`
  and `backend/convex/pushQueue.ts`, including the game-registry import graph.
  Preserve exact badge counts, access checks and notification privacy. jemalloc
  reduces allocator retention; these queries need separate profiling.
- [ ] Before launch, measure mixed traffic from multiple couples with realistic
  histories and device counts, including subscription invalidations, writes,
  media and push bursts. Record latency, errors and resource use to establish a
  capacity budget and identify the next bottleneck. The earlier single-couple
  uncached badge workload is not a production user-capacity estimate.
- [ ] Trace the `usage_tracking` message `Failed to find component path despite
  thresholds being exceeded` to the operation that emits it and check for an
  upstream fix. It appeared around successful exports and exists in the old
  source too. Its lack of application impact is inferred from source and the
  passing checks, rather than a dedicated telemetry test.
- [ ] Review a stable successor to `cc07c9e` when available. Rehearse the candidate
  and recovery with the shared runtime procedure before replacing the prerelease.
  Keep SQLite and R2 checkpoints consistent, and preserve
  `STORAGE_MAX_INTERMEDIATE_PART_SIZE=5242880`.
