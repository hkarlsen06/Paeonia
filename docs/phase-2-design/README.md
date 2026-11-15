# Design foundation

Brand and design-system decisions adopted before feature implementation. The code under `ios/PaeoniaApp/Shared/DesignSystem/` holds the tokens (colors, spacing, radii, typography, motion, haptics), and `ios/PaeoniaApp/Shared/DesignSystem/Components/` holds the reusable components.

## Documents

- [Design principles](./01-design-principles.md)
- [Core components](./04-core-components.md)
- [Motion and haptics](./05-motion-and-haptics.md)
- [Widget visual language](./06-widget-visual-language.md)
- [Voice and copy](./07-voice-and-copy.md)
- [Accessibility](./08-accessibility.md)
- [Marketing brand guidelines](./09-marketing-brand-guidelines.md)

## Hard rules

- Do not hardcode colors directly in feature views.
- Do not invent one-off spacing values without a reason. Name the value as a local constant.
- Do not make the UI childish, gamified, or guilt-driven.
- Do not make private couple content feel public or social-media-like.
- Keep feature UI inside `Features/<FeatureName>/`. Shared components go in `Shared/` only when reusable.

## Locked direction

- Overall feel: premium calm.
- One plum-led brand theme. No separate light and dark app appearances for MVP.
- Components are slightly custom on top of native iOS, not fully stock controls.
- Haptics are subtle in normal use and tactile for key relationship moments.
- Apple system typography everywhere, including marketing. No brand font, no decorative romance font.
- Dates and numbers use system formatting (`FormatStyle`), never hand-built strings.

## Open release decision

The icon material and depth treatment in Apple Icon Composer. It must keep the delivered logo and app-icon mark as the baseline and be checked across the app, widget and App Store assets.
