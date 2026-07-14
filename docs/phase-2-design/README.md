# Phase 2 Design Foundation

Status: implemented design foundation and ongoing reference. This folder records the brand and design-system decisions adopted before feature implementation; it is not an active project phase or release tracker.

The goal is not to freeze every visual detail. The goal is to make the app easier to build consistently from the locked Paeonia logo, app-icon mark, and plum-led color baseline.

## Current Status

| Area | Status | Notes |
| --- | --- | --- |
| App icon | Baseline decided | Delivered mark and Icon Composer exports are canonical. Final target/App Store validation remains on the MVP release checklist. |
| Color system | Decided | Paeonia uses a single plum-led brand theme. No separate light/dark app themes for MVP. |
| Typography | Decided | Use SF/system typography across native app and marketing for MVP. |
| Spacing/radius tokens | Decided | Use a small semantic scale, not ad hoc values. |
| Component primitives | Decided | Buttons, cards, sheets, fields, empty states, alerts, paywall cards. |
| Motion/haptics | Decided | Calm, purposeful, never noisy. |
| Widget visual language | Documented | Central product surface. Drawing-first, intimate, low-clutter. |
| Voice/copy | Documented | Warm, direct, private, not guilt-driven. |

## Documents

- [Design Principles](./01-design-principles.md)
- [Design Tokens](./02-design-tokens.md)
- [Typography](./03-typography.md)
- [Core Components](./04-core-components.md)
- [Motion And Haptics](./05-motion-and-haptics.md)
- [Widget Visual Language](./06-widget-visual-language.md)
- [Voice And Copy](./07-voice-and-copy.md)
- [Accessibility](./08-accessibility.md)
- [Marketing Brand Guidelines](./09-marketing-brand-guidelines.md)

## Hard Rules

- Do not hardcode colors directly in feature views.
- Do not invent one-off spacing values unless there is a clear reason.
- Do not make the UI childish, gamified, or guilt-driven.
- Do not make private couple content feel public or social-media-like.
- Keep feature UI inside `Features/<FeatureName>/`; shared components go in `Shared/` only when genuinely reusable.
- All user-facing strings must go through String Catalog symbols.
- All user-facing copy must be understandable to an ordinary 16-year-old and must not expose technical implementation wording.
- Accessibility is part of the design system, not a later cleanup step.

## Locked Direction

- Overall feel: premium calm.
- Theme: one canonical plum-led brand theme. Do not design separate light and dark app appearances for MVP.
- Component feel: slightly custom on top of native iOS, not fully stock controls.
- Haptics: subtle in normal use, tactile for key relationship moments.
- Typography: SF/system typography everywhere, including marketing. No separate brand font for MVP.

## Remaining Release Decision

The foundation is implemented. One release-asset decision remains open:

- icon material/depth treatment in Apple Icon Composer

The delivered logo and app-icon mark are the canonical visual baseline for marketing and native app color direction. Final material/depth tuning must preserve that baseline and be validated across the app, widget, and App Store assets before release.
