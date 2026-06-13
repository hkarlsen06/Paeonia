# Typography

The native app and marketing site should use Apple system typography for MVP.

This keeps Paeonia accessible, localizable, Dynamic Type-friendly, and visually native.

## Decision

- Native app: Apple system font.
- Marketing site: Apple/system font.
- App icon: no text.
- Wordmark: optional later, separate from the app icon.

There is no separate brand typography direction for MVP. Use SF/system typography across app and marketing.

## Text Roles

Define roles by meaning, not by one-off font sizes.

| Role | Use |
| --- | --- |
| `display` | rare hero text, onboarding headline |
| `largeTitle` | main screen title |
| `title` | feature title |
| `sectionTitle` | section headers |
| `body` | normal readable text |
| `bodyEmphasis` | important body copy |
| `caption` | metadata/supporting text |
| `button` | button labels |
| `countdownNumber` | large milestone/countdown numbers |
| `widgetPrimary` | main widget text |
| `widgetSecondary` | secondary widget text |

## Native Role Mapping

Initial SwiftUI mapping:

| Role | SwiftUI Font |
| --- | --- |
| `display` | `.largeTitle.bold()` |
| `largeTitle` | `.largeTitle.weight(.semibold)` |
| `title` | `.title2.weight(.semibold)` |
| `sectionTitle` | `.headline` |
| `body` | `.body` |
| `bodyEmphasis` | `.body.weight(.semibold)` |
| `caption` | `.caption` |
| `button` | `.headline` |
| `countdownNumber` | `.system(.largeTitle, design: .rounded).weight(.bold)` |
| `widgetPrimary` | `.headline` |
| `widgetSecondary` | `.caption` |

Use these roles as helpers so feature code does not scatter font choices.

## Tone In Typography

Typography should feel calm and confident:

- avoid oversized hype headlines
- avoid tiny gray explanatory copy
- use generous line height for emotional and legal copy
- keep button labels short
- keep onboarding headlines warm and simple

## Dynamic Type

All core app screens must support Dynamic Type.

Rules:

- Avoid fixed-height containers around text.
- Avoid truncating emotional or legal text.
- Use `minimumScaleFactor` only for constrained visual elements like widgets/countdowns, not normal copy.
- Test onboarding, paywall, settings, memory cards, and prompt answers at larger text sizes.

Acceptance criteria:

- no clipped primary actions at accessibility sizes
- no hidden legal/paywall terms
- prompt answers and memory notes remain readable
- countdown/milestone numbers can scale or reflow without losing meaning

## Numbers And Dates

Use system formatting:

- `FormatStyle` for dates and relative dates
- locale-aware number formatting
- no hand-built date strings

Milestone countdowns should be emotionally legible, not just mathematically accurate.

Good:

```text
12 days until your 6-month milestone
```

Avoid:

```text
Anniversary in 12d
```

## Marketing Typography

Marketing should use the same system typography direction as the app:

- calm
- premium
- intimate
- readable

Do not introduce a decorative romance font.
