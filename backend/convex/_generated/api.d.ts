/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as access from "../access.js";
import type * as accountDeletion from "../accountDeletion.js";
import type * as catalog from "../catalog.js";
import type * as chatPresence from "../chatPresence.js";
import type * as crons from "../crons.js";
import type * as daily from "../daily.js";
import type * as drawAndGuess from "../drawAndGuess.js";
import type * as games from "../games.js";
import type * as http from "../http.js";
import type * as identity from "../identity.js";
import type * as lib_access from "../lib/access.js";
import type * as lib_accountDeletion from "../lib/accountDeletion.js";
import type * as lib_accountDeletionProviders from "../lib/accountDeletionProviders.js";
import type * as lib_apns from "../lib/apns.js";
import type * as lib_apnsDrain from "../lib/apnsDrain.js";
import type * as lib_appleNotificationVerifier from "../lib/appleNotificationVerifier.js";
import type * as lib_appleStoreKit from "../lib/appleStoreKit.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_clientOperationArgs from "../lib/clientOperationArgs.js";
import type * as lib_clientOperations from "../lib/clientOperations.js";
import type * as lib_coupleDays from "../lib/coupleDays.js";
import type * as lib_crypto from "../lib/crypto.js";
import type * as lib_dailyAnswers from "../lib/dailyAnswers.js";
import type * as lib_dailyQuestions from "../lib/dailyQuestions.js";
import type * as lib_db from "../lib/db.js";
import type * as lib_drawAndGuess from "../lib/drawAndGuess.js";
import type * as lib_entitlements from "../lib/entitlements.js";
import type * as lib_errors from "../lib/errors.js";
import type * as lib_gameRegistry from "../lib/gameRegistry.js";
import type * as lib_gameWords from "../lib/gameWords.js";
import type * as lib_games from "../lib/games.js";
import type * as lib_ids from "../lib/ids.js";
import type * as lib_json from "../lib/json.js";
import type * as lib_liveTicket from "../lib/liveTicket.js";
import type * as lib_mediaAssets from "../lib/mediaAssets.js";
import type * as lib_mediaOrphans from "../lib/mediaOrphans.js";
import type * as lib_mindMeld from "../lib/mindMeld.js";
import type * as lib_notificationCopy from "../lib/notificationCopy.js";
import type * as lib_notifications from "../lib/notifications.js";
import type * as lib_profiles from "../lib/profiles.js";
import type * as lib_relationshipBlock from "../lib/relationshipBlock.js";
import type * as lib_relationshipCleanup from "../lib/relationshipCleanup.js";
import type * as lib_relationshipEnd from "../lib/relationshipEnd.js";
import type * as lib_relationshipState from "../lib/relationshipState.js";
import type * as lib_reportTargets from "../lib/reportTargets.js";
import type * as lib_reports from "../lib/reports.js";
import type * as lib_reviewAccess from "../lib/reviewAccess.js";
import type * as lib_storekit from "../lib/storekit.js";
import type * as lib_storyChain from "../lib/storyChain.js";
import type * as lib_streakDeadlines from "../lib/streakDeadlines.js";
import type * as lib_streaks from "../lib/streaks.js";
import type * as lib_syncEvents from "../lib/syncEvents.js";
import type * as lib_text from "../lib/text.js";
import type * as lib_time from "../lib/time.js";
import type * as lib_validators from "../lib/validators.js";
import type * as location from "../location.js";
import type * as media from "../media.js";
import type * as memories from "../memories.js";
import type * as mindMeld from "../mindMeld.js";
import type * as moderation from "../moderation.js";
import type * as pairing from "../pairing.js";
import type * as push from "../push.js";
import type * as pushQueue from "../pushQueue.js";
import type * as relationship from "../relationship.js";
import type * as reports from "../reports.js";
import type * as review from "../review.js";
import type * as storekit from "../storekit.js";
import type * as storekitNode from "../storekitNode.js";
import type * as storyChain from "../storyChain.js";
import type * as streaks from "../streaks.js";
import type * as threads from "../threads.js";
import type * as widget from "../widget.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  access: typeof access;
  accountDeletion: typeof accountDeletion;
  catalog: typeof catalog;
  chatPresence: typeof chatPresence;
  crons: typeof crons;
  daily: typeof daily;
  drawAndGuess: typeof drawAndGuess;
  games: typeof games;
  http: typeof http;
  identity: typeof identity;
  "lib/access": typeof lib_access;
  "lib/accountDeletion": typeof lib_accountDeletion;
  "lib/accountDeletionProviders": typeof lib_accountDeletionProviders;
  "lib/apns": typeof lib_apns;
  "lib/apnsDrain": typeof lib_apnsDrain;
  "lib/appleNotificationVerifier": typeof lib_appleNotificationVerifier;
  "lib/appleStoreKit": typeof lib_appleStoreKit;
  "lib/auth": typeof lib_auth;
  "lib/clientOperationArgs": typeof lib_clientOperationArgs;
  "lib/clientOperations": typeof lib_clientOperations;
  "lib/coupleDays": typeof lib_coupleDays;
  "lib/crypto": typeof lib_crypto;
  "lib/dailyAnswers": typeof lib_dailyAnswers;
  "lib/dailyQuestions": typeof lib_dailyQuestions;
  "lib/db": typeof lib_db;
  "lib/drawAndGuess": typeof lib_drawAndGuess;
  "lib/entitlements": typeof lib_entitlements;
  "lib/errors": typeof lib_errors;
  "lib/gameRegistry": typeof lib_gameRegistry;
  "lib/gameWords": typeof lib_gameWords;
  "lib/games": typeof lib_games;
  "lib/ids": typeof lib_ids;
  "lib/json": typeof lib_json;
  "lib/liveTicket": typeof lib_liveTicket;
  "lib/mediaAssets": typeof lib_mediaAssets;
  "lib/mediaOrphans": typeof lib_mediaOrphans;
  "lib/mindMeld": typeof lib_mindMeld;
  "lib/notificationCopy": typeof lib_notificationCopy;
  "lib/notifications": typeof lib_notifications;
  "lib/profiles": typeof lib_profiles;
  "lib/relationshipBlock": typeof lib_relationshipBlock;
  "lib/relationshipCleanup": typeof lib_relationshipCleanup;
  "lib/relationshipEnd": typeof lib_relationshipEnd;
  "lib/relationshipState": typeof lib_relationshipState;
  "lib/reportTargets": typeof lib_reportTargets;
  "lib/reports": typeof lib_reports;
  "lib/reviewAccess": typeof lib_reviewAccess;
  "lib/storekit": typeof lib_storekit;
  "lib/storyChain": typeof lib_storyChain;
  "lib/streakDeadlines": typeof lib_streakDeadlines;
  "lib/streaks": typeof lib_streaks;
  "lib/syncEvents": typeof lib_syncEvents;
  "lib/text": typeof lib_text;
  "lib/time": typeof lib_time;
  "lib/validators": typeof lib_validators;
  location: typeof location;
  media: typeof media;
  memories: typeof memories;
  mindMeld: typeof mindMeld;
  moderation: typeof moderation;
  pairing: typeof pairing;
  push: typeof push;
  pushQueue: typeof pushQueue;
  relationship: typeof relationship;
  reports: typeof reports;
  review: typeof review;
  storekit: typeof storekit;
  storekitNode: typeof storekitNode;
  storyChain: typeof storyChain;
  streaks: typeof streaks;
  threads: typeof threads;
  widget: typeof widget;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
