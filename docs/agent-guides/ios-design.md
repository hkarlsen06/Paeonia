# Design System

Use semantic colors and design tokens. Do not scatter hardcoded colors, spacing, or typography values through feature views.

Paeonia uses one canonical plum-led brand theme for MVP. Do not design or implement separate light and dark native app appearances unless the user explicitly reopens that product decision. Accessibility settings still matter: preserve Dynamic Type, Reduce Motion, contrast, and VoiceOver behavior within the plum theme.

Suggested semantic colors:

- `paeoniaBackground`
- `paeoniaBackgroundSecondary`
- `paeoniaSurfacePrimary`
- `paeoniaSurfaceSecondary`
- `paeoniaTextPrimary`
- `paeoniaTextSecondary`
- `paeoniaTextMuted`
- `paeoniaAccent`
- `paeoniaError`
- `paeoniaSuccess`
- `paeoniaWarning`

Also centralize:

- spacing
- corner radii
- typography roles
- animation durations
- haptic patterns
- reusable button and card styles

Use cards only when the framed surface has product meaning, such as a distinct repeated item, modal, or tool. Prefer few or no cards, and do not wrap ordinary screen content in cards by default. Place content directly in the screen layout with intentional spacing and hierarchy. Put primary CTA clusters near the bottom of the screen when it improves thumb reach and matches the flow. In bottom button clusters, text-only actions without visible button backgrounds should still occupy button-sized hit targets and be spaced like adjacent buttons, not tucked close to the primary CTA.

### Brand Wordmark

- When `Paeonia` is shown as a standalone single-word app name in the iOS app or widget surfaces, use the shared `PaeoniaWordmark` logo lockup in the app target, or the same mark-left, serif, semibold wordmark treatment in targets that cannot import it.
- Size may change with layout hierarchy, but the wordmark font treatment should stay consistent.
- When `app.tagline` is presented as the slogan paired with the stylized wordmark, use `PaeoniaBrandLockup` so the logo-plus-wordmark row is constrained to the same visual width as the tagline. Use the same serif, semibold wordmark family treatment at the appropriate size for that layout.
- Do not apply the wordmark style automatically when `Paeonia` appears as part of a sentence or longer phrase; use the surrounding copy style in those cases.

### Error Presentation

- Present transient user-facing errors through the app-level top dropdown banner.
- Mount the shared banner once at the root and send feature errors into that shared surface.
- Do not add new inline red error panels or system alerts for ordinary recoverable errors.
- Keep full-screen error states only when the whole screen cannot continue and needs a retry action.

### Confirmation Dialogs

- Confirmations and destructive choices use the centered system alert dialog, app-wide. Use SwiftUI `.alert(_:isPresented:actions:message:)`.
- Do not use `.confirmationDialog` (the bottom action sheet) for these. It anchors to the bottom or renders as a popover and is not the intended presentation.
- This is separate from error presentation: errors still go to the top banner (see above); the centered alert is only for confirmations the user must explicitly approve (for example: clear canvas, delete account, leave relationship).
- Title states the action, the message states the consequence and reversibility, the destructive button uses a verb with the `.destructive` role, and the cancel button uses the `.cancel` role.
