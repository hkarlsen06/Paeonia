/**
 * The `deeplink` of a push that opens one memory or one story. The app reads these in
 * `PaeoniaDeepLink` (ios/PaeoniaApp/Services/Notifications/PaeoniaDeepLink.swift), so change the
 * two together. A push about a comment or a reply passes the flag that opens the conversation too.
 */

/** Opens the memory. With `comments`, also its comments. */
export function memoryDeepLink(memoryId: string, options: { comments?: boolean } = {}): string {
  return `paeonia://memories/memory?memoryId=${memoryId}${options.comments ? "&comments=1" : ""}`;
}

/** Opens the story in the viewer. With `replies`, also its replies. */
export function storyDeepLink(storyId: string, options: { replies?: boolean } = {}): string {
  return `paeonia://stories/story?storyId=${storyId}${options.replies ? "&replies=1" : ""}`;
}
