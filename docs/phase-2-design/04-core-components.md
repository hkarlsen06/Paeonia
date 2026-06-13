# Core Components

This document defines Paeonia's reusable component primitives. It does not define final colors.

Components should be native, calm, slightly custom, and consistent. They should make feature work faster without creating an overbuilt design system too early.

The component direction is **slightly custom iOS**, not plain stock controls. Components may use custom shapes, spacing, materials, and pressed states, but they must keep native accessibility, gestures, focus, and platform behavior.

Implementation target:

```text
ios/PaeoniaApp/Shared/DesignSystem/Components/
```

Create components only when used by a real screen. Do not build an unused component gallery in MVP.

## Buttons

### Primary Button

Use for the main action on a screen.

Examples:

- continue onboarding
- accept invite
- answer prompt
- create memory
- subscribe

Rules:

- one primary button per decision area
- full-width on onboarding/paywall
- clear label, no clever copy
- disabled state must explain itself when needed

Implementation name: `PaeoniaPrimaryButtonStyle`.

### Secondary Button

Use for alternative but valid actions.

Examples:

- restore purchases
- remind me later
- add note later

Implementation name: `PaeoniaSecondaryButtonStyle`.

### Quiet Button

Use for low-emphasis utility actions.

Examples:

- edit
- skip optional photo
- change date

Implementation name: `PaeoniaQuietButtonStyle`.

### Destructive Button

Use only for destructive or relationship-affecting actions.

Examples:

- leave relationship
- delete memory
- delete account

Destructive flows require confirmation copy that explains consequence and reversibility.

Implementation name: `PaeoniaDestructiveButtonStyle`.

## Cards

Cards are the main content container.

Card types:

- `PromptCard`
- `MemoryCard`
- `MilestoneCard`
- `WidgetPreviewCard`
- `SubscriptionCard`
- `SettingsCard`
- `SyncStatusCard`

Rules:

- cards should feel contained and private
- avoid dense borders and heavy shadows
- prefer one primary content idea per card
- if a card contains partner content, make ownership/state clear

Implementation should start with one reusable `PaeoniaCard` container. Feature-specific cards should compose it rather than subclassing or creating unrelated card styles.

## Sheets

Use sheets for focused tasks, not whole app flows.

Good sheet uses:

- add memory note
- attach media
- edit relationship date
- notification permission explanation
- confirm leave relationship

Avoid nesting sheets more than one level deep.

## Fields

Field types:

- text input
- multiline note input
- date picker
- invite code input
- voice note title/metadata field if needed

Rules:

- labels should be visible or strongly implied by context
- validation should be specific
- invite code input should tolerate spaces/case differences
- text-note fields must feel safe and private, not like a public post composer

Invite code fields should visually support grouping/chunking without forcing users to type separators.

## Empty States

Empty states are product moments. They should explain what happens next without shaming the user.

Required empty states:

- no partner yet
- partner invited, waiting for accept
- no daily prompt answer yet
- partner has not answered yet
- no memories yet
- no widget drawing yet
- no voice notes yet
- offline with no cached content

Tone:

- warm
- direct
- useful
- never guilt-driven

## Alerts And Confirmations

Use alerts for urgent confirmations and destructive choices.

Important confirmations:

- leave relationship
- delete account
- delete memory
- discard unsynced local changes, if ever needed
- stop subscription flow, if user would lose access

Rules:

- title states the action
- body states consequence
- destructive button uses a verb
- cancellation is clear

## Paywall Components

The paywall is hard, but it must be honest and App Review-safe.

Required elements:

- product value
- price
- billing period
- renewal behavior
- trial terms, if any
- restore purchases
- manage subscription link where appropriate
- note that one paying partner unlocks access for both

Avoid manipulative countdowns or fake urgency.

## Sync Status

Sync status should be visible only where useful.

States:

- saved locally
- syncing
- synced
- sync failed
- offline

Do not make normal offline use feel broken.

Sync copy must describe user impact, not implementation state.

Use:

```text
Saved on this phone
Sending when you're online
Sent to your partner
```

Avoid:

```text
Pending sync
Queued mutation
Remote write failed
```

## Navigation Shell

Use `NavigationStack` for feature flows unless there is a clear reason not to.

The root app state decides which high-level shell is shown:

- unauthenticated
- onboarding
- unpaired
- paired
- paywalled

Do not let feature screens independently decide global auth/pairing/paywall state.
