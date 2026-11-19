# Design system

Use semantic colors and design tokens. Do not scatter hardcoded colors, spacing, or typography values through feature views. `paeoniaCardSurface` owns card edges and the glow for content waiting for this person. `paeoniaEyebrowStyle` owns small uppercase labels. `PaeoniaIllustratedCard` owns the shared picture, title and action layout. Its shared shape also sizes context-menu previews.

`ios/PaeoniaShared/PaeoniaPalette.swift` owns the palette and the brand roles shared by the app and widget. Their default accent comes from the single `AccentColor` asset in `PaeoniaShared/BrandAssets.xcassets`. Topics choose decorative hues through `TopicStyle`, independently of success, warning and drawing ink roles.

Paeonia uses one canonical plum-led brand theme for MVP. Do not design or implement separate light and dark native app appearances unless the user explicitly reopens that product decision. Accessibility settings still matter: preserve Dynamic Type, Reduce Motion, contrast, and VoiceOver behavior within the plum theme.

Use the semantic color names in `PaeoniaPalette.swift`, such as `paeoniaSurfaceHighlight` for permanent highlighted fills and `paeoniaSurfacePressed` for press feedback. Spacing, radii, typography, animation durations, haptics, and button and card styles are shared too. Reuse them.

Use cards only when the framed surface has product meaning, such as a distinct repeated item, modal, or tool. Prefer few or no cards, and do not wrap ordinary screen content in cards by default. Place content directly in the screen layout with intentional spacing and hierarchy. Put primary CTA clusters near the bottom of the screen when it improves thumb reach and matches the flow. Pin a bottom button bar with `paeoniaBottomBar` (`Shared/DesignSystem/PaeoniaKeyboard.swift`), not a bare `safeAreaInset`, so the keyboard covers the bar instead of pushing it up into the keyboard's Done button. Only inputs that belong above the keyboard, like a chat composer, should ride up with it. A screen that can show a keyboard sets its background with `paeoniaScreenBackground()` (`Shared/DesignSystem/PaeoniaColors.swift`). A plain `.background(.paeoniaBackgroundPrimary)` stops at the keyboard's top edge, and black shows beside the iOS 26 keyboard's rounded corners. In bottom button clusters, text-only actions without visible button backgrounds should still occupy button-sized hit targets and be spaced like adjacent buttons, not tucked close to the primary CTA.

Chats, Games and Memories use inline navigation titles. More has no toolbar title. Us keeps its custom map header. Shared button styles provide vertical padding as well as a minimum tap height. Use `PaeoniaCircularButtonStyle` for the compact circular actions in composers. The paywall lets its purchase controls scroll at accessibility text sizes or when they would occupy more than half the available height.

### Animating a view in

An entrance that starts when a view appears or first lays out, such as a fade and drop, animates its own modifiers with `.animation(_:body:)`. Do not put `.animation(_:value:)` on it. That form animates every layout change in the update where the value flips, and a new screen's first real layout lands in that same update, so each part glides in from where the empty first pass put it and the screen seems to grow out of a corner. `screenEntrance(order:)` and `launchEntrance(order:)` (`Features/Auth/LaunchReveal.swift`) already do this, so use them for a screen's cascade.

### iPad layout

The app runs on iPhone and iPad, and on iPad it can be any width from a narrow Split View column to full landscape. Build one adaptive layout, not a separate iPad design.

- Put `.paeoniaReadableWidth()` on a screen's content inside its scroll view, so content stops at `PaeoniaSpacing.readableContentWidth` and the background still reaches the screen edges. Bottom button bars get the same cap.
- The welcome, onboarding, paywall, pairing, and pairing celebration screens use the narrower `PaeoniaSpacing.focusedContentWidth`. `PaeoniaScreenFrame` already applies it.
- Size from the space the view is given, not from `UIScreen` or the device type. Check new screens on an iPad simulator in portrait and landscape, and in a narrow window. To get one, open the app on the Shared iPad and drag the window's bottom trailing corner, or long-press the green window control and pick a size. Check it on the Shared iPhone Duo too, unfolded and folded (`scripts/scenario-screenshot <scenario-id> --duo`, then `--fold closed`). An unfolded Duo has a regular width but is still an iPhone to `userInterfaceIdiom`.
- In an iPad window the close and resize controls sit in the top leading corner. A navigation bar keeps its items clear of them. A screen that draws its own top row instead puts `.containerCornerOffset(.leading, sizeToFit: true)` on that row, as Home's header does.

### Tap targets

Every control takes taps over at least 44 by 44 points. A button with `.buttonStyle(.plain)` takes taps only on what its label draws, so a 44-point `frame` around a glyph needs `.contentShape(Rectangle())` after it, unless a filled background covers the frame. In a compact row, put `paeoniaTapTarget()` on the label, so the target reaches into the row's padding without making the row taller. `AccessibilityReleaseChecksUITests` reads the frames and fails below 44 points.

### List rows

Every row in a list or settings screen uses primary text and tints its icon with `paeoniaAccentPrimary`. Rows on the More tab's menu draw their label with `SettingsMenuLabel`, which puts the symbol on a soft plum tile and shows the row's state in secondary text at the end. Pushed settings screens keep plain glyphs, except the date rows that the Important dates screen reuses from the menu. Only irreversible destructive actions, such as leaving the relationship or deleting the account, are red. Do not use system blue, warning colours or per-row accents. `paeoniaGroupedList()` sets the brand tint for native `List` and `Form` screens.

### Brand wordmark

- When `Paeonia` is shown as a standalone single-word app name in the iOS app or widget surfaces, use the shared `PaeoniaWordmark` logo lockup in the app target, or the same mark-left, serif, semibold wordmark treatment in targets that cannot import it.
- Size may change with layout hierarchy, but the wordmark font treatment should stay consistent.
- When `app.tagline` is presented as the slogan paired with the stylized wordmark, use `PaeoniaBrandLockup` so the logo-plus-wordmark row is constrained to the same visual width as the tagline. Use the same serif, semibold wordmark family treatment at the appropriate size for that layout.
- Do not apply the wordmark style automatically when `Paeonia` appears as part of a sentence or longer phrase; use the surrounding copy style in those cases.

### Error presentation

Routine local saves and queued uploads show no status message. Visible content is saved, and the queue sends it when the connection returns. Keep failed-send warnings and retry controls when the person can take action. A drawing that the person has not chosen to send can still say "Not sent yet".

- Present transient user-facing errors through the shared bottom glass banner.
- Send feature errors to the shared banner center. The paired tabs host it above the native tab bar, using the selected tab's content bounds. Bottom action bars and chat composers publish their top edge so the banner stays above their controls. Other root screens, sheets and covers mount `.paeoniaBanner` themselves, and only the frontmost host draws it.
- Game notices show the game's existing illustrated hub object. Other notices use a contextual symbol, such as a drawing tool, chat bubbles, a calendar or a download arrow. Partner avatars remain available for personal updates.
- Use untinted system glass and primary text so the banner matches the native tab bar. Keep its height compact, let long messages and Dynamic Type grow, and preserve VoiceOver announcements, Reduce Motion and Reduce Transparency. Swipe down dismisses it. Errors and actionable notices stay until dismissed. Passive notices disappear after four seconds unless VoiceOver is running.
- Do not add new inline red error panels or system alerts for ordinary recoverable errors.
- Keep full-screen error states only when the whole screen cannot continue and needs a retry action.

### Confirmation dialogs

- Confirmations and destructive choices use the centered system alert dialog, app-wide. Use SwiftUI `.alert(_:isPresented:actions:message:)`.
- Do not use `.confirmationDialog` (the bottom action sheet) for these. It anchors to the bottom or renders as a popover and is not the intended presentation.
- Errors still go to the bottom banner. The centered alert is only for confirmations, such as clear canvas, delete account and leave relationship.
- Title states the action, the message states the consequence and reversibility, the destructive button uses a verb with the `.destructive` role, and the cancel button uses the `.cancel` role.
