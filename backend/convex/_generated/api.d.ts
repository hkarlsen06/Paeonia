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
import type * as admin from "../admin.js";
import type * as analytics from "../analytics.js";
import type * as boardGames from "../boardGames.js";
import type * as catalog from "../catalog.js";
import type * as chatPresence from "../chatPresence.js";
import type * as consensio from "../consensio.js";
import type * as countdowns from "../countdowns.js";
import type * as crons from "../crons.js";
import type * as daily from "../daily.js";
import type * as dailyQuestionChat from "../dailyQuestionChat.js";
import type * as drawAndGuess from "../drawAndGuess.js";
import type * as exquisiteCorpse from "../exquisiteCorpse.js";
import type * as firstDay from "../firstDay.js";
import type * as games from "../games.js";
import type * as hearts from "../hearts.js";
import type * as http from "../http.js";
import type * as identity from "../identity.js";
import type * as lib_access from "../lib/access.js";
import type * as lib_accountDeletion from "../lib/accountDeletion.js";
import type * as lib_accountDeletionProviders from "../lib/accountDeletionProviders.js";
import type * as lib_apns from "../lib/apns.js";
import type * as lib_appleNotificationVerifier from "../lib/appleNotificationVerifier.js";
import type * as lib_appleStoreKit from "../lib/appleStoreKit.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_backgroundWorkpool from "../lib/backgroundWorkpool.js";
import type * as lib_bans from "../lib/bans.js";
import type * as lib_boardGameBackend from "../lib/boardGameBackend.js";
import type * as lib_boardGameRules from "../lib/boardGameRules.js";
import type * as lib_boardGameStore from "../lib/boardGameStore.js";
import type * as lib_boardGames from "../lib/boardGames.js";
import type * as lib_clientOperationArgs from "../lib/clientOperationArgs.js";
import type * as lib_clientOperations from "../lib/clientOperations.js";
import type * as lib_connectFour from "../lib/connectFour.js";
import type * as lib_consensio from "../lib/consensio.js";
import type * as lib_coupleDays from "../lib/coupleDays.js";
import type * as lib_crypto from "../lib/crypto.js";
import type * as lib_dailyAnswers from "../lib/dailyAnswers.js";
import type * as lib_dailyQuestionRounds from "../lib/dailyQuestionRounds.js";
import type * as lib_dailyQuestions from "../lib/dailyQuestions.js";
import type * as lib_db from "../lib/db.js";
import type * as lib_dotsAndBoxes from "../lib/dotsAndBoxes.js";
import type * as lib_drawAndGuess from "../lib/drawAndGuess.js";
import type * as lib_entitlements from "../lib/entitlements.js";
import type * as lib_errors from "../lib/errors.js";
import type * as lib_exquisiteCorpse from "../lib/exquisiteCorpse.js";
import type * as lib_exquisiteCorpseIdeas from "../lib/exquisiteCorpseIdeas.js";
import type * as lib_firstDay from "../lib/firstDay.js";
import type * as lib_gameRegistry from "../lib/gameRegistry.js";
import type * as lib_gameWords from "../lib/gameWords.js";
import type * as lib_games from "../lib/games.js";
import type * as lib_hearts from "../lib/hearts.js";
import type * as lib_ids from "../lib/ids.js";
import type * as lib_json from "../lib/json.js";
import type * as lib_liveTicket from "../lib/liveTicket.js";
import type * as lib_lockScreenState from "../lib/lockScreenState.js";
import type * as lib_lookBack from "../lib/lookBack.js";
import type * as lib_ludo from "../lib/ludo.js";
import type * as lib_mediaAssets from "../lib/mediaAssets.js";
import type * as lib_mediaOrphans from "../lib/mediaOrphans.js";
import type * as lib_mindMeld from "../lib/mindMeld.js";
import type * as lib_notificationCopy from "../lib/notificationCopy.js";
import type * as lib_notifications from "../lib/notifications.js";
import type * as lib_presence from "../lib/presence.js";
import type * as lib_profiles from "../lib/profiles.js";
import type * as lib_questionTime from "../lib/questionTime.js";
import type * as lib_questionTimeStatus from "../lib/questionTimeStatus.js";
import type * as lib_rateLimits from "../lib/rateLimits.js";
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
import type * as lib_topics from "../lib/topics.js";
import type * as lib_ultimateTicTacToe from "../lib/ultimateTicTacToe.js";
import type * as lib_validators from "../lib/validators.js";
import type * as lib_widgetDrawings from "../lib/widgetDrawings.js";
import type * as location from "../location.js";
import type * as lookBack from "../lookBack.js";
import type * as media from "../media.js";
import type * as memories from "../memories.js";
import type * as mindMeld from "../mindMeld.js";
import type * as moderation from "../moderation.js";
import type * as pairing from "../pairing.js";
import type * as push from "../push.js";
import type * as pushQueue from "../pushQueue.js";
import type * as questionTime from "../questionTime.js";
import type * as relationship from "../relationship.js";
import type * as reports from "../reports.js";
import type * as retention from "../retention.js";
import type * as review from "../review.js";
import type * as storekit from "../storekit.js";
import type * as storekitNode from "../storekitNode.js";
import type * as stories from "../stories.js";
import type * as storyChain from "../storyChain.js";
import type * as streaks from "../streaks.js";
import type * as threads from "../threads.js";
import type * as topics from "../topics.js";
import type * as widget from "../widget.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  access: typeof access;
  accountDeletion: typeof accountDeletion;
  admin: typeof admin;
  analytics: typeof analytics;
  boardGames: typeof boardGames;
  catalog: typeof catalog;
  chatPresence: typeof chatPresence;
  consensio: typeof consensio;
  countdowns: typeof countdowns;
  crons: typeof crons;
  daily: typeof daily;
  dailyQuestionChat: typeof dailyQuestionChat;
  drawAndGuess: typeof drawAndGuess;
  exquisiteCorpse: typeof exquisiteCorpse;
  firstDay: typeof firstDay;
  games: typeof games;
  hearts: typeof hearts;
  http: typeof http;
  identity: typeof identity;
  "lib/access": typeof lib_access;
  "lib/accountDeletion": typeof lib_accountDeletion;
  "lib/accountDeletionProviders": typeof lib_accountDeletionProviders;
  "lib/apns": typeof lib_apns;
  "lib/appleNotificationVerifier": typeof lib_appleNotificationVerifier;
  "lib/appleStoreKit": typeof lib_appleStoreKit;
  "lib/auth": typeof lib_auth;
  "lib/backgroundWorkpool": typeof lib_backgroundWorkpool;
  "lib/bans": typeof lib_bans;
  "lib/boardGameBackend": typeof lib_boardGameBackend;
  "lib/boardGameRules": typeof lib_boardGameRules;
  "lib/boardGameStore": typeof lib_boardGameStore;
  "lib/boardGames": typeof lib_boardGames;
  "lib/clientOperationArgs": typeof lib_clientOperationArgs;
  "lib/clientOperations": typeof lib_clientOperations;
  "lib/connectFour": typeof lib_connectFour;
  "lib/consensio": typeof lib_consensio;
  "lib/coupleDays": typeof lib_coupleDays;
  "lib/crypto": typeof lib_crypto;
  "lib/dailyAnswers": typeof lib_dailyAnswers;
  "lib/dailyQuestionRounds": typeof lib_dailyQuestionRounds;
  "lib/dailyQuestions": typeof lib_dailyQuestions;
  "lib/db": typeof lib_db;
  "lib/dotsAndBoxes": typeof lib_dotsAndBoxes;
  "lib/drawAndGuess": typeof lib_drawAndGuess;
  "lib/entitlements": typeof lib_entitlements;
  "lib/errors": typeof lib_errors;
  "lib/exquisiteCorpse": typeof lib_exquisiteCorpse;
  "lib/exquisiteCorpseIdeas": typeof lib_exquisiteCorpseIdeas;
  "lib/firstDay": typeof lib_firstDay;
  "lib/gameRegistry": typeof lib_gameRegistry;
  "lib/gameWords": typeof lib_gameWords;
  "lib/games": typeof lib_games;
  "lib/hearts": typeof lib_hearts;
  "lib/ids": typeof lib_ids;
  "lib/json": typeof lib_json;
  "lib/liveTicket": typeof lib_liveTicket;
  "lib/lockScreenState": typeof lib_lockScreenState;
  "lib/lookBack": typeof lib_lookBack;
  "lib/ludo": typeof lib_ludo;
  "lib/mediaAssets": typeof lib_mediaAssets;
  "lib/mediaOrphans": typeof lib_mediaOrphans;
  "lib/mindMeld": typeof lib_mindMeld;
  "lib/notificationCopy": typeof lib_notificationCopy;
  "lib/notifications": typeof lib_notifications;
  "lib/presence": typeof lib_presence;
  "lib/profiles": typeof lib_profiles;
  "lib/questionTime": typeof lib_questionTime;
  "lib/questionTimeStatus": typeof lib_questionTimeStatus;
  "lib/rateLimits": typeof lib_rateLimits;
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
  "lib/topics": typeof lib_topics;
  "lib/ultimateTicTacToe": typeof lib_ultimateTicTacToe;
  "lib/validators": typeof lib_validators;
  "lib/widgetDrawings": typeof lib_widgetDrawings;
  location: typeof location;
  lookBack: typeof lookBack;
  media: typeof media;
  memories: typeof memories;
  mindMeld: typeof mindMeld;
  moderation: typeof moderation;
  pairing: typeof pairing;
  push: typeof push;
  pushQueue: typeof pushQueue;
  questionTime: typeof questionTime;
  relationship: typeof relationship;
  reports: typeof reports;
  retention: typeof retention;
  review: typeof review;
  storekit: typeof storekit;
  storekitNode: typeof storekitNode;
  stories: typeof stories;
  storyChain: typeof storyChain;
  streaks: typeof streaks;
  threads: typeof threads;
  topics: typeof topics;
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

export declare const components: {
  pushWorkpool: import("@convex-dev/workpool/_generated/component.js").ComponentApi<"pushWorkpool">;
  backgroundWorkpool: import("@convex-dev/workpool/_generated/component.js").ComponentApi<"backgroundWorkpool">;
  rateLimiter: import("@convex-dev/rate-limiter/_generated/component.js").ComponentApi<"rateLimiter">;
  presence: import("@convex-dev/presence/_generated/component.js").ComponentApi<"presence">;
};
