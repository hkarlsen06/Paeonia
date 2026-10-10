import { httpRouter } from "convex/server";
import { serve_media } from "./media";
import { apple_server_notifications } from "./storekit";

// The single HTTP router. Feature modules export httpActions and mount them here.
const http = httpRouter();

// Apple App Store Server Notifications V2 (replaces the apple-server-notifications Edge Function).
http.route({ path: "/apple/server-notifications", method: "POST", handler: apple_server_notifications });

// Signed media downloads (replaces Supabase Storage signed URLs). See media.ts.
http.route({ path: "/media", method: "GET", handler: serve_media });

export default http;
