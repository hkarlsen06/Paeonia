import presence from "@convex-dev/presence/convex.config.js";
import rateLimiter from "@convex-dev/rate-limiter/convex.config.js";
import workpool from "@convex-dev/workpool/convex.config.js";
import { defineApp } from "convex/server";

const app = defineApp();
// Sends APNs pushes. See push.ts.
app.use(workpool, { name: "pushWorkpool" });
// Report snapshot copies, media blob deletes, and Clerk account deletes.
app.use(workpool, { name: "backgroundWorkpool" });
app.use(rateLimiter);
app.use(presence);

export default app;
