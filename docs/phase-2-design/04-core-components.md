# Core components

Components are native, calm and slightly custom. They may use custom shapes, spacing, materials and pressed states, but keep native accessibility, gestures and behavior. Create a component only when a real screen uses it.

## Buttons

- One primary button per decision area. Full-width on onboarding and the paywall.
- Destructive buttons are for destructive or relationship-affecting actions only. The flow confirms with copy that explains the consequence and whether it can be undone.

## Cards

- Cards feel contained and private. Avoid dense borders and heavy shadows.
- One main idea per card. A card that shows partner content makes ownership clear.
- Feature cards compose `PaeoniaCard`. They do not make unrelated card styles.

## Sheets

Sheets are for focused tasks, not whole flows. Do not nest sheets more than one level.

## Fields

- Labels are visible or strongly implied.
- Validation is specific.
- Invite code input tolerates spaces and case differences, and does not force separators.
- Text-note fields feel private, not like a public post composer.

## Empty states

Empty states are product moments. They say what happens next, never shame the user, and are warm and direct. Every state where the user waits on something (no partner yet, invited and waiting, partner has not answered, offline with no cache) has one.

## Alerts and confirmations

- The title states the action. The body states the consequence. The destructive button uses a verb. Cancel is clear.
- Use the centered system alert (SwiftUI `.alert`) app-wide. Do not use a bottom action sheet (`.confirmationDialog`).

## Paywall

The paywall is hard, so it must be honest and App Review-safe. It shows value, price, billing period, renewal behavior, trial terms if any, restore purchases, a manage-subscription link where appropriate, and that one paying partner unlocks access for both. No manipulative countdowns or fake urgency.

## Sync status

Routine local saves and queued uploads show no status line, including while offline. Show a failed-send warning and retry only when the person can act. A drawing not yet submitted can say "Not sent yet", and a delivered one "Sent". Never expose pending operations or other implementation terms.

## Navigation

Feature flows use `NavigationStack`. The root app state decides the shell (unauthenticated, onboarding, unpaired, paired, paywalled). Feature screens never decide global auth, pairing or paywall state.
